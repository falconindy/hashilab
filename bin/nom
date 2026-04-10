#!/usr/bin/env python3

import argparse
import glob
import json
import os
import random
import re
import shlex
import shutil
import subprocess
import sys
import threading
from typing import List, Optional


def run_cmd(cmd, check=True, capture_output=True, text=True, input=None):
    res = subprocess.run(
        cmd, check=check, capture_output=capture_output, text=text, input=input
    )
    return res


def nomad_json(*args):
    res = run_cmd(["nomad"] + list(args), check=False)
    if res.returncode == 0 and res.stdout.strip():
        try:
            return json.loads(res.stdout)
        except json.JSONDecodeError:
            pass
    return None


def is_uuid(s):
    return re.fullmatch(r"[0-9a-fA-F\-]+", s) is not None


def resolve_all(arg: str) -> List[tuple]:
    if is_uuid(arg):
        data = nomad_json("alloc", "status", "-json", arg)
        allocs = [data] if data else []
    else:
        allocs = nomad_json("job", "allocs", "-json", arg) or []

    running = [a for a in allocs if a.get("ClientStatus") == "running"]

    res = []
    for a in running:
        node_name = a.get("NodeName", "")
        alloc_id = a.get("ID", "")
        res.append((alloc_id, node_name))

    res.sort(key=lambda x: (x[1], x[0]))
    return res


def resolve_any(arg: str) -> Optional[str]:
    all_allocs = resolve_all(arg)
    if not all_allocs:
        return None
    return random.choice(all_allocs)[0]


def get_job_name(job_file: str) -> Optional[str]:
    data = nomad_json("run", "-output", job_file)
    if data and "Job" in data and "Name" in data["Job"]:
        return data["Job"]["Name"]
    return None


def job_is_running(job_file: str) -> bool:
    jobname = get_job_name(job_file)
    if not jobname:
        return False
    res = run_cmd(["nomad", "job", "status", jobname], check=False, capture_output=True)
    return res.returncode == 0


def cmd_lookupallocs(args):
    for alloc_id, node in resolve_all(args.arg):
        print(f"{alloc_id} {node}")
    return True


def cmd_diff(args):
    job_file = args.job
    jobname = get_job_name(job_file)
    if not jobname:
        return False

    current_res = run_cmd(["nomad", "job", "inspect", "-hcl", jobname], check=False)
    if current_res.returncode != 0 or not current_res.stdout:
        return False
    current_hcl = current_res.stdout

    proc = subprocess.Popen(
        [
            "diff",
            "-u",
            "--label",
            f"{job_file} (current)",
            "-",
            "--label",
            f"{job_file} (future)",
            job_file,
        ],
        stdin=subprocess.PIPE,
        text=True,
    )
    proc.communicate(input=current_hcl)
    return proc.returncode


def cmd_prepull(args):
    job_file = args.job
    out = nomad_json("run", "-output", job_file)
    if not out:
        return False

    images = set()
    for tg in out.get("Job", {}).get("TaskGroups", []):
        for task in tg.get("Tasks", []):
            if task.get("Driver") == "docker":
                img = task.get("Config", {}).get("image")
                if img:
                    images.add(img)
    if not images:
        return True

    images = sorted(list(images))
    dcs = out.get("Job", {}).get("Datacenters", [])

    nodes_status = nomad_json("node", "status", "-json")
    if not nodes_status:
        return False

    nodes = []
    for node in nodes_status:
        if "*" in dcs or node.get("Datacenter") in dcs:
            if node.get("Name"):
                nodes.append(node.get("Name"))
    nodes.sort()

    print(f"Pulling image(s) to nodes: {' '.join(nodes)}")
    for img in images:
        print(f" * {img}")

    import concurrent.futures

    success = True

    def pull_images_on_node(node):
        logfile = f"/tmp/prepull.{node}"
        with open(logfile, "w") as fout:
            for img in images:
                cmd = ["ssh", f"{node}.node.home", "docker", "pull", img]
                res = subprocess.run(cmd, stdout=fout, stderr=fout)
                if res.returncode == 0:
                    print(f"SUCCESS: [{img}] prepull done on {node}")
                else:
                    print(f"ERROR: prepull on {node} failed; check {logfile}")
                    return False
        try:
            os.remove(logfile)
        except OSError:
            pass
        return True

    with concurrent.futures.ThreadPoolExecutor(max_workers=len(nodes) or 1) as executor:
        futures = [executor.submit(pull_images_on_node, n) for n in nodes]
        for f in concurrent.futures.as_completed(futures):
            if not f.result():
                success = False

    return 0 if success else 1


def cmd_prepull_and_push(args):
    res = cmd_prepull(args)
    if res == 0 or res is True:
        return subprocess.run(["nomad", "run", args.job]).returncode
    return 1


def cmd_endpoint(args):
    resolves = [r[0] for r in resolve_all(args.arg)]
    if not resolves:
        return 1

    for r in resolves:
        data = nomad_json("alloc", "status", "-json", r)
        if not data:
            continue

        node_name = data.get("NodeName", "")
        ports = data.get("AllocatedResources", {}).get("Shared", {}).get("Ports", [])

        lines = []
        for p in ports:
            lines.append(
                f"{node_name}\t{p.get('Label')}:\thttp://{p.get('HostIP')}:{p.get('Value')}"
            )

        if lines:
            proc = subprocess.Popen(["column", "-t"], stdin=subprocess.PIPE, text=True)
            proc.communicate(input="\n".join(lines) + "\n")
            print()
    return True


def cmd_exec(args):
    if args.host:
        resolves = [r[0] for r in resolve_all(args.arg) if r[1] == args.host]
        resolved = resolves[0] if resolves else None
    else:
        resolved = resolve_any(args.arg)

    if not resolved:
        return 1

    exec_args = ["nomad", "alloc", "exec"]
    if args.task:
        exec_args.extend(["-task", args.task])
    exec_args.extend(["-t", "-i", resolved])
    cmd_args = args.cmd_args if args.cmd_args else ["/bin/sh"]
    exec_args.extend(cmd_args)

    return subprocess.run(exec_args).returncode


def cmd_ui(args):
    nomad_args = ["-authenticate"]
    if (
        os.environ.get("SSH_CONNECTION")
        or not shutil.which("xdg-open")
        or args.show_url
    ):
        nomad_args.append("-show-url")

    return subprocess.run(["nomad", "ui"] + nomad_args + args.rest).returncode


def cmd_drain(args):
    node_name = args.node_name
    data = nomad_json("node", "status", "-json", "-filter", f'Name=="{node_name}"')
    if not data or not isinstance(data, list):
        print(f"ERROR: no node known by name: {node_name}", file=sys.stderr)
        return 1
    node_id = data[0].get("ID")
    return subprocess.run(["nomad", "node", "drain", "-enable", node_id]).returncode


def cmd_undrain(args):
    node_name = args.node_name
    data = nomad_json("node", "status", "-json", "-filter", f'Name=="{node_name}"')
    if not data or not isinstance(data, list):
        print(f"ERROR: no node known by name: {node_name}", file=sys.stderr)
        return 1
    node_id = data[0].get("ID")
    return subprocess.run(
        ["nomad", "node", "eligibility", "-enable", node_id]
    ).returncode


def cmd_stale(args):
    for f in args.files:
        import io
        import contextlib

        with contextlib.redirect_stdout(io.StringIO()):
            res = cmd_diff(argparse.Namespace(job=f))
        if res != 0:
            print(f)
    return True


def cmd_integrate(args):
    re_pattern = args.re_pattern
    res = subprocess.run(
        ["git", "branch", "--format=%(refname)", "-r", "--list", "origin/renovate/*"],
        capture_output=True,
        text=True,
    )
    branches = []
    for line in res.stdout.splitlines():
        parts = line.split("/")
        if len(parts) >= 3 and re.search(re_pattern, parts[-1]):
            branches.append(f"{parts[-3]}/{parts[-2]}/{parts[-1]}")

    if len(branches) == 0:
        print(f"ERROR: no branches found by name: {re_pattern}", file=sys.stderr)
        return False
    elif len(branches) > 1:
        print(f"ERROR: multiple branches found by name: {re_pattern}", file=sys.stderr)
        for b in branches:
            print(f"  * {b}")
        return False

    refname = branches[0]
    show_res = subprocess.run(
        ["git", "show", "--format=", "--name-only", refname],
        capture_output=True,
        text=True,
    )
    updated_jobs = [j for j in show_res.stdout.splitlines() if j.strip()]
    if not updated_jobs:
        return False

    parts = refname.split("/", 1)
    if len(parts) == 2:
        remote, branch = parts
        if subprocess.run(["git", "pull", remote, branch]).returncode != 0:
            return False

    for job in updated_jobs:
        if job_is_running(job):
            cmd_prepull_and_push(argparse.Namespace(job=job))

    return True


def get_parsers():
    parsers = []

    p = argparse.ArgumentParser(prog="diff")
    p.add_argument("job")
    p.set_defaults(func=cmd_diff)
    parsers.append(p)

    p = argparse.ArgumentParser(prog="drain")
    p.add_argument("node_name")
    p.set_defaults(func=cmd_drain)
    parsers.append(p)

    p = argparse.ArgumentParser(prog="endpoint")
    p.add_argument("arg")
    p.set_defaults(func=cmd_endpoint)
    parsers.append(p)

    p = argparse.ArgumentParser(prog="exec", add_help=False)
    p.add_argument("-t", dest="task")
    p.add_argument("-h", dest="host")
    p.add_argument("arg")
    p.add_argument("cmd_args", nargs=argparse.REMAINDER)
    p.set_defaults(func=cmd_exec)
    parsers.append(p)

    p = argparse.ArgumentParser(prog="integrate")
    p.add_argument("re_pattern")
    p.set_defaults(func=cmd_integrate)
    parsers.append(p)

    p = argparse.ArgumentParser(prog="lookupallocs")
    p.add_argument("arg")
    p.set_defaults(func=cmd_lookupallocs)
    parsers.append(p)

    p = argparse.ArgumentParser(prog="prepull")
    p.add_argument("job")
    p.set_defaults(func=cmd_prepull)
    parsers.append(p)

    p = argparse.ArgumentParser(prog="prepull_and_push")
    p.add_argument("job")
    p.set_defaults(func=cmd_prepull_and_push)
    parsers.append(p)

    p = argparse.ArgumentParser(prog="stale")
    p.add_argument("files", nargs="+")
    p.set_defaults(func=cmd_stale)
    parsers.append(p)

    p = argparse.ArgumentParser(prog="ui")
    p.add_argument("-show-url", action="store_true")
    p.add_argument("rest", nargs=argparse.REMAINDER)
    p.set_defaults(func=cmd_ui)
    parsers.append(p)

    p = argparse.ArgumentParser(prog="undrain")
    p.add_argument("node_name")
    p.set_defaults(func=cmd_undrain)
    parsers.append(p)

    return parsers


ALIASES = {
    "la": "lookupallocs",
    "ep": "endpoint",
    "pp": "prepull",
    "ppp": "prepull_and_push",
}


def known_commands(parsers):
    print("Known commands:")
    for p in parsers:
        print(f"\t{p.prog}")


def run_command(cmd, args):
    if cmd in ALIASES:
        cmd = ALIASES[cmd]

    parsers = get_parsers()
    matches = [p for p in parsers if p.prog.startswith(cmd)]

    match len(matches):
        case 1:
            parser = matches[0]
            parsed_args = parser.parse_args(args)
            if hasattr(parsed_args, "func"):
                res = parsed_args.func(parsed_args)
                if isinstance(res, bool):
                    return 0 if res else 1
                elif isinstance(res, int):
                    return res
                return 0
            return 0
        case 0:
            print(f"ERROR: no such command: {cmd}", file=sys.stderr)
            known_commands(parsers)
            return 1
        case _:
            matched_names = [p.prog for p in matches]
            print(
                f"ERROR: ambiguous command prefix: {' '.join(matched_names)}",
                file=sys.stderr,
            )
            return 1


def main():
    if len(sys.argv) < 2:
        known_commands(get_parsers())
        sys.exit(1)

    cmd = sys.argv[1]
    args = sys.argv[2:]
    sys.exit(run_command(cmd, args))


if __name__ == "__main__":
    main()
