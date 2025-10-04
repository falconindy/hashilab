#!/usr/bin/env python3

from dataclasses import dataclass
from types import TracebackType

import ipaddress
import logging
import hvac
import paramiko
import tempfile
import subprocess
import sys

logger = logging.getLogger('certctl')


def SetupLogger():
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
        cmdline = ("sudo", "mount", self._nfs_path, self._tempdir.name)
        subprocess.run(cmdline)
        return self

    def __exit__(self, exc_type: type[BaseException] | None,
                 exc_value: BaseException | None,
                 exc_traceback: TracebackType | None) -> None:
        cmdline = ("sudo", "umount", self._tempdir.name)
        subprocess.run(cmdline)

    def write_file(self, dest: str, contents: str) -> None:
        p = subprocess.Popen(("sudo", "tee", f"{self._tempdir.name}/{dest}"),
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

    def __enter__(self) -> None:
        self._client.connect(self._host)
        return self

    def __exit__(self, exc_type: type[BaseException] | None,
                 exc_value: BaseException | None,
                 exc_traceback: TracebackType | None) -> None:
        self._client.close()

    def write_file(self, dest: str, contents: str, sudo: bool = False) -> None:
        if sudo:
            stdin, stdout, stderr = self._client.exec_command(
                f"sudo tee >/dev/null {dest}")
        else:
            stdin, stdout, stderr = self._client.exec_command(f"tee >{dest}")

        stdin.write(contents.encode())
        stdin.close()

        error = stderr.read().decode()
        if error:
            print(error, file=sys.stderr)
            # raise?

    def reload_service(self, service) -> None:
        stdin, stdout, stderr = self._client.exec_command(
            f"sudo systemctl reload {service}")

        error = stderr.read().decode()
        if error:
            print(error, file=sys.stderr)
            # raise?


class CertGenerator:

    DEFAULT_TTL = "4390h"

    def _is_ip_address(self, ip_string: str) -> bool:
        """
        Checks if a given string is a valid IPV4 or IPV6 address.
        Returns True if valid, False otherwise.
        """
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
        """
        Generates a new certificate.
        """

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


@dataclass
class Server:
    hostname: str
    ip_address: str


def renew_vault_certificates():
    servers = (
        Server('nomad0.node.home', '10.0.100.100'),
        Server('nomad1.node.home', '10.0.100.101'),
        Server('nomad2.node.home', '10.0.100.102'),
    )

    generator = CertGenerator()
    for server in servers:
        logger.info(f'generating certificate for {server}')
        cert = generator.generate(mount_point='pki_int',
                                  role='vault-servers',
                                  common_name='vault.service.home',
                                  sans=[
                                      server.ip_address,
                                      'localhost',
                                      '127.0.0.1',
                                      'active.vault.service.home',
                                      'standby.vault.service.home',
                                  ])

        formatter = CertificateResponseFormatter(cert)
        with SshCertDeployer(server.hostname) as d:
            logger.info(f'writing new certificates')
            d.write_file('/opt/vault/tls/home-ca.pem',
                         formatter.ca_chain(),
                         sudo=True)
            d.write_file('/opt/vault/tls/tls.crt',
                         formatter.certificate(),
                         sudo=True)
            d.write_file('/opt/vault/tls/tls.key',
                         formatter.private_key(),
                         sudo=True)
            d.write_file('/opt/vault/tls/listener.pem',
                         formatter.certificate(fullchain=True),
                         sudo=True)
            logger.info(f'reloading vault')
            d.reload_service('vault')


def renew_omada_certificate():
    logger.info('renewing certificates for omada-controller')
    server = Server('bastion.node.home', '10.0.1.99')

    generator = CertGenerator()
    cert = generator.generate(mount_point='pki_int',
                              role='vault-servers',
                              common_name='omada-controller.service.home',
                              sans=[
                                  server.ip_address,
                              ])
    logger.info('new certificates generated')

    formatter = CertificateResponseFormatter(cert)
    with NfsCertDeployer('nasty.node.home:/volume1/omada-controller') as d:
        d.write_file('cert/tls.crt', formatter.certificate(fullchain=True))
        d.write_file('cert/tls.key', formatter.private_key())

    logger.info('new certificates deployed')

    logger.info('restarting omada-controller job')
    subprocess.run(("nomad", "job", "restart", "omada-controller"))


if __name__ == '__main__':
    SetupLogger()

    if sys.argv[1] == "omada":
        renew_omada_certificate()
    elif sys.argv[1] == "vault":
        renew_vault_certificates()
    else:
        logger.error(f'no known certificate: {sys.argv[1]}')
