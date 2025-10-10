#!/usr/bin/env python3

from dataclasses import dataclass
from types import TracebackType
from enum import Enum, auto

import ipaddress
import logging
import hvac
import os
import paramiko
import tempfile
import subprocess
import sys


class OSFlavor(Enum):
    DEBIAN = auto()
    SYNOLOGY = auto()


@dataclass(frozen=True)
class Server:
    hostname: str
    ip_address: str
    os: OSFlavor = OSFlavor.DEBIAN
    has_vault: bool = False
    has_consul: bool = False
    has_nomad: bool = False


CLUSTER_SERVERS = (
    Server(hostname='nomad0.node.home',
           ip_address='10.0.100.100',
           has_vault=True,
           has_consul=True,
           has_nomad=True),
    Server(hostname='nomad1.node.home',
           ip_address='10.0.100.101',
           has_vault=True,
           has_consul=True,
           has_nomad=True),
    Server(hostname='nomad2.node.home',
           ip_address='10.0.100.102',
           has_vault=True,
           has_consul=True,
           has_nomad=True),
)

CLUSTER_CLIENTS = (
    Server(hostname='nasty.node.home',
           ip_address='10.0.100.50',
           os=OSFlavor.SYNOLOGY,
           has_consul=True),
    Server(hostname='bastion.node.home',
           ip_address='10.0.1.99',
           has_consul=True,
           has_nomad=True),
)

logger = logging.getLogger('certctl')


def SetupLogger() -> None:
    formatter = logging.Formatter('%(asctime)s %(levelname)s: %(message)s',
                                  datefmt='%Y-%m-%d %H:%M:%S')

    handler = logging.StreamHandler()
    handler.setFormatter(formatter)

    logger.setLevel(logging.INFO)
    logger.addHandler(handler)


@dataclass
class CertificateResponse:
    ca_chain: str
    certificate: str
    private_key: str
    expiration: int
    serial_number: str


class CertificateResponseFormatter:

    def __init__(self, cert: CertificateResponse) -> None:
        self._cert = cert

    def private_key(self) -> str:
        return self._cert.private_key

    def certificate(self, fullchain: bool = False) -> str:
        pem = [self._cert.certificate]
        if fullchain:
            pem.append(self._cert.ca_chain)
        return '\n'.join(pem)

    def ca_chain(self) -> str:
        return self._cert.ca_chain


class NfsCertDeployer:

    def __init__(self, nfs_path) -> None:
        self._nfs_path = nfs_path
        self._tempdir = tempfile.TemporaryDirectory()

    def __enter__(self):
        cmdline = ('sudo', 'mount', self._nfs_path, self._tempdir.name)
        subprocess.run(cmdline)
        return self

    def __exit__(self, exc_type: type[BaseException] | None,
                 exc_value: BaseException | None,
                 exc_traceback: TracebackType | None) -> None:
        cmdline = ('sudo', 'umount', self._tempdir.name)
        subprocess.run(cmdline)

    def write_file(self, dest: str, contents: str) -> None:
        p = subprocess.Popen(('sudo', 'tee', f'{self._tempdir.name}/{dest}'),
                             stdin=subprocess.PIPE,
                             stdout=subprocess.PIPE,
                             stderr=subprocess.PIPE)
        p.communicate(input=contents.encode())


class SshCertDeployer:

    def __init__(self, host) -> None:
        self._client = paramiko.client.SSHClient()
        self._client.load_system_host_keys()
        self._client.set_missing_host_key_policy(paramiko.client.WarningPolicy)
        self._host = host

        self._ssh_config = paramiko.config.SSHConfig()
        with open(os.path.expanduser('~/.ssh/config')) as f:
            self._ssh_config.parse(f)

    def __enter__(self) -> None:
        host_config = self._ssh_config.lookup(self._host)
        self._client.connect(self._host,
                             username=host_config.get('user', None))
        return self

    def __exit__(self, exc_type: type[BaseException] | None,
                 exc_value: BaseException | None,
                 exc_traceback: TracebackType | None) -> None:
        self._client.close()

    def write_file(self, dest: str, contents: str, sudo: bool = False) -> None:
        if sudo:
            stdin, stdout, stderr = self._client.exec_command(
                f'sudo tee >/dev/null {dest}')
        else:
            stdin, stdout, stderr = self._client.exec_command(f'tee >{dest}')

        stdin.write(contents.encode())
        stdin.close()

        error = stderr.read().decode()
        if error:
            raise subprocess.CalledProcessError(error.strip())

    def reload_service(self, service: str, os: OSFlavor) -> None:
        if os == OSFlavor.SYNOLOGY:
            # there's no reload verb, sadly.
            stdin, stdout, stderr = self._client.exec_command(
                f'sudo synopkg restart {service}')
        else:  # assume debian (and sanity)
            stdin, stdout, stderr = self._client.exec_command(
                f'sudo systemctl reload {service}')

        error = stderr.read().decode()
        if error:
            # don't raise an exception, try to reload everything
            print(error, file=sys.stderr, end='')


class CertGenerator:

    DEFAULT_TTL = '4390h'

    def _is_ip_address(self, ip_string: str) -> bool:
        '''
        Checks if a given string is a valid IPV4 or IPV6 address.
        Returns True if valid, False otherwise.
        '''
        try:
            ipaddress.ip_address(ip_string)
            return True
        except ValueError:
            return False

    def __init__(self) -> None:
        self._client = hvac.Client(url='https://vault.service.home:8200',
                                   verify='/etc/ssl/certs/home.pem')

    def generate(self,
                 mount_point: str,
                 role: str,
                 common_name: str,
                 sans: list[str] = [],
                 ttl: str = DEFAULT_TTL) -> CertificateResponse:
        '''Generates a new certificate.'''

        ip_sans: list[str] = list()
        alt_names: list[str] = list()
        for name in sans:
            if self._is_ip_address(name):
                ip_sans.append(name)
            else:
                alt_names.append(name)

        extra_params: dict[str, str] = {}
        if ip_sans:
            extra_params['ip_sans'] = ','.join(ip_sans)
        if alt_names:
            extra_params['alt_names'] = ','.join(alt_names)
        if ttl:
            extra_params['ttl'] = ttl

        response = self._client.secrets.pki.generate_certificate(
            name=role,
            common_name=common_name,
            mount_point=mount_point,
            extra_params=extra_params)

        return CertificateResponse('\n'.join(response['data']['ca_chain']),
                                   response['data']['certificate'],
                                   response['data']['private_key'],
                                   response['data']['expiration'],
                                   response['data']['serial_number'])


def deploy_hcl_certs(prog, deployer, formatter) -> None:
    tls_path = f'/opt/{prog}/tls'

    deployer.write_file(f'{tls_path}/home-ca.pem',
                        formatter.ca_chain(),
                        sudo=True)
    deployer.write_file(f'{tls_path}/tls.crt',
                        formatter.certificate(fullchain=True),
                        sudo=True)
    deployer.write_file(f'{tls_path}/tls.key',
                        formatter.private_key(),
                        sudo=True)


def renew_nomad_certificates() -> None:
    certs = dict()
    generator = CertGenerator()
    for server in CLUSTER_SERVERS:
        if not server.has_nomad:
            continue

        logger.info(f'generating certificate for {server.hostname}')
        certs[server] = generator.generate(mount_point='pki_int_internal',
                                           role='intermediate',
                                           common_name='nomad.service.home',
                                           sans=[
                                               server.ip_address,
                                               'server.global.nomad',
                                               'localhost',
                                               '127.0.0.1',
                                           ])

    for server in CLUSTER_CLIENTS:
        if not server.has_nomad:
            continue

        logger.info(f'generating certificate for {server.hostname}')
        certs[server] = generator.generate(mount_point='pki_int_internal',
                                           role='intermediate',
                                           common_name='nomad.service.home',
                                           sans=[
                                               server.ip_address,
                                               'client.global.nomad',
                                               'localhost',
                                               '127.0.0.1',
                                           ])

    for server, cert in certs.items():
        formatter = CertificateResponseFormatter(cert)

        with SshCertDeployer(server.hostname) as d:
            logger.info(f'writing new certificates to {server.hostname}')
            deploy_hcl_certs('nomad', d, formatter)

            logger.info(f'reloading nomad on {server.hostname}')
            d.reload_service('nomad', os=server.os)


def renew_consul_certificates() -> None:
    certs = dict()
    generator = CertGenerator()
    for server in CLUSTER_SERVERS:
        if not server.has_consul:
            continue

        logger.info(f'generating certificate for {server.hostname}')
        certs[server] = generator.generate(mount_point='pki_int_internal',
                                           role='intermediate',
                                           common_name='consul.service.home',
                                           sans=[
                                               'server.global.home',
                                               '127.0.0.1',
                                               'localhost',
                                           ])

    for server in CLUSTER_CLIENTS:
        if not server.has_consul:
            continue

        logger.info(f'generating certificate for {server.hostname}')
        certs[server] = generator.generate(mount_point='pki_int_internal',
                                           role='intermediate',
                                           common_name='consul.service.home',
                                           sans=[
                                               'client.global.home',
                                               '127.0.0.1',
                                               'localhost',
                                           ])

    for server, cert in certs.items():
        formatter = CertificateResponseFormatter(cert)
        with SshCertDeployer(server.hostname) as d:
            logger.info(f'writing new certificates to {server.hostname}')
            deploy_hcl_certs('consul', d, formatter)

            logger.info(f'reloading consul on {server.hostname}')
            d.reload_service('consul', os=server.os)


def renew_vault_certificates() -> None:
    certs = dict()
    generator = CertGenerator()
    for server in CLUSTER_SERVERS:
        if not server.has_vault:
            continue

        logger.info(f'generating certificate for {server.hostname}')
        certs[server] = generator.generate(mount_point='pki_int_internal',
                                           role='intermediate',
                                           common_name='vault.service.home',
                                           sans=[
                                               server.ip_address,
                                               'localhost',
                                               '127.0.0.1',
                                               '172.17.0.1',
                                               'active.vault.service.home',
                                               'standby.vault.service.home',
                                           ])

    for server, cert in certs.items():
        formatter = CertificateResponseFormatter(cert)
        with SshCertDeployer(server.hostname) as d:
            logger.info(f'writing new certificates to {server.hostname}')
            deploy_hcl_certs('vault', d, formatter)

            logger.info(f'reloading vault on {server.hostname}')
            d.reload_service('vault', os=server.os)


def renew_omada_certificates() -> None:
    logger.info('renewing certificates for omada-controller')

    generator = CertGenerator()
    cert = generator.generate(mount_point='pki_int',
                              role='intermediate',
                              common_name='omada-controller.service.home',
                              sans=[
                                  '10.0.1.99',
                              ])
    logger.info('new certificates generated')

    formatter = CertificateResponseFormatter(cert)
    with NfsCertDeployer('nasty.node.home:/volume1/omada-controller') as d:
        d.write_file('cert/tls.crt', formatter.certificate(fullchain=True))
        d.write_file('cert/tls.key', formatter.private_key())

    logger.info('new certificates deployed')

    logger.info('restarting omada-controller job')
    subprocess.run(('nomad', 'job', 'restart', 'omada-controller'))


if __name__ == '__main__':
    SetupLogger()

    if len(sys.argv) < 2:
        print('ERROR: no system name supplied', file=sys.stderr)
        print('usage: certctl <certname>', file=sys.stderr)
        sys.exit(1)

    certname = sys.argv[1]
    renew_fn = globals().get(f'renew_{certname}_certificates', None)
    if renew_fn:
        renew_fn()
    else:
        logger.error(f'no known certificate: {certname}')
