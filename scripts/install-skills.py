#!/usr/bin/env python3
import argparse
import json
import os
from pathlib import Path
import re
import shlex
import shutil
import subprocess
import sys
import tempfile
from urllib.parse import urlsplit


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError(f"duplicate JSON key: {key}")
        result[key] = value
    return result


def valid_source(source):
    if (
        not isinstance(source, str)
        or not source
        or not source.isprintable()
        or any(c.isspace() for c in source)
    ):
        return False
    if re.fullmatch(r"[A-Za-z0-9_-]+/[A-Za-z0-9_.-]+", source):
        return True
    url = urlsplit(source)
    return (
        url.scheme == "https"
        and bool(url.hostname)
        and url.username is None
        and url.password is None
        and not url.query
        and not url.fragment
    )


def load_commands(path):
    manifest = json.loads(path.read_text(), object_pairs_hook=unique_object)
    if not isinstance(manifest, dict) or set(manifest) != {"cliVersion", "sources"}:
        raise ValueError("manifest requires only cliVersion and sources")
    version = manifest["cliVersion"]
    if not isinstance(version, str) or not re.fullmatch(r"\d+\.\d+\.\d+", version):
        raise ValueError("cliVersion must be an exact stable version")
    if not isinstance(manifest["sources"], list):
        raise ValueError("sources must be a list")
    commands = []
    seen = set()
    for entry in manifest["sources"]:
        if not isinstance(entry, dict) or set(entry) != {"source", "skills"}:
            raise ValueError("each source requires only source and skills")
        if not valid_source(entry["source"]):
            raise ValueError("source must be owner/repo or a credential-free HTTPS URL")
        skills = entry["skills"]
        if not isinstance(skills, list) or not skills:
            raise ValueError("each source must select at least one named skill")
        for skill in skills:
            if (
                not isinstance(skill, str)
                or len(skill) > 64
                or not re.fullmatch(r"[a-z0-9]+(?:-[a-z0-9]+)*", skill)
            ):
                raise ValueError("skill names must be lowercase kebab-case, not wildcards")
            if skill in seen:
                raise ValueError(f"duplicate skill name: {skill}")
            seen.add(skill)
        commands.append([
            "npx", "--yes", f"skills@{version}", "add", entry["source"],
            "--global", "--agent", "universal", "--skill", *skills, "--yes",
        ])
    return commands


def main():
    parser = argparse.ArgumentParser(description="Install declared global skills with npx skills.")
    parser.add_argument(
        "--manifest", type=Path, default=Path(__file__).resolve().with_name("skills.json")
    )
    parser.add_argument("--dry-run", action="store_true", help="validate and print commands only")
    args = parser.parse_args()
    commands = load_commands(args.manifest)
    if not commands:
        print("No skills declared; nothing to install.")
        return
    for command in commands:
        print(shlex.join(command), flush=True)
    if args.dry_run:
        return
    if not shutil.which("npx"):
        raise ValueError("npx is required; install Node.js and npm first")
    scratch_root = Path.home() / ".local/state/agents/tmp"
    scratch_root.mkdir(mode=0o700, parents=True, exist_ok=True)
    task_dir = tempfile.mkdtemp(prefix="skills-install.", dir=scratch_root)
    print(f"Retained installation workspace: {task_dir}", flush=True)
    env = os.environ.copy()
    env["TMPDIR"] = task_dir
    env["DISABLE_TELEMETRY"] = "1"
    for command in commands:
        subprocess.run(command, env=env, check=True)


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError) as error:
        print(f"install-skills: {error}", file=sys.stderr)
        sys.exit(1)
    except subprocess.CalledProcessError as error:
        print(f"install-skills: installer failed (exit {error.returncode})", file=sys.stderr)
        sys.exit(1)
