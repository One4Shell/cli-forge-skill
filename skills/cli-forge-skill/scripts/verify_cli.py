#!/usr/bin/env python3
"""verify_cli.py — mechanical verification matrix for a cli-forge-skill CLI.

Usage:
    python3 verify_cli.py <binary> [command...] [--module <dir>] [--verbose]

Probes are run for each positional command (`<binary> <cmd>` and
`<binary> <cmd> --json`) plus automatic probes for `--help`, `--version`,
`help`, and a bad-flag usage error. Asserts the cli-forge-skill output contract:

    - exit codes are 0 (success), 1 (runtime failure), 2 (usage error)
    - on success, stdout is exactly one parseable JSON document (in --json)
      and stderr is empty
    - on failure, stdout is empty and stderr carries the structured error
    - piped (non-TTY) stdout/stderr contain no ANSI escapes, and NO_COLOR=1 is
      respected

With `--module <dir>`, additionally runs `go vet ./...` and `go test ./...` in
that directory. Exits 0 only when every check passes.
"""
from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path

ESCAPE = b"\x1b"


def run(binary: str, args: list[str], env_extra: dict[str, str] | None = None) -> subprocess.CompletedProcess:
    env = None
    if env_extra:
        import os

        env = dict(os.environ)
        env.update(env_extra)
    return subprocess.run([binary] + args, capture_output=True, env=env, timeout=60)


def has_ansi(data: bytes) -> bool:
    return ESCAPE in data


def checks(failures: list[str], verbose: bool, label: str, proc: subprocess.CompletedProcess,
           expect_json_success: bool = True) -> None:
    verb = ""
    if verbose:
        verb = f"\n  stdout={proc.stdout!r}\n  stderr={proc.stderr!r}"
    if proc.returncode not in (0, 1, 2):
        failures.append(f"[FAIL] {label}: unexpected exit code {proc.returncode}{verb}")
    if has_ansi(proc.stdout) or has_ansi(proc.stderr):
        failures.append(f"[FAIL] {label}: ANSI escape detected in piped output{verb}")
    if proc.returncode == 0:
        if expect_json_success:
            try:
                json.loads(proc.stdout.decode("utf-8"))
            except ValueError as e:
                failures.append(f"[FAIL] {label} --json: stdout is not valid JSON ({e}){verb}")
        if proc.stderr.strip():
            failures.append(f"[FAIL] {label}: success but stderr is non-empty{verb}")
        else:
            print(f"[PASS] {label}: exit 0, clean stdout/stderr")
    else:
        if proc.stdout.strip():
            failures.append(f"[FAIL] {label}: failure but stdout is non-empty{verb}")
        if not proc.stderr.strip():
            failures.append(f"[FAIL] {label}: failure but stderr is empty{verb}")
        else:
            try:
                err = json.loads(proc.stderr.decode("utf-8"))
                if not (isinstance(err, dict) and err.get("ok") is False and "error" in err
                        and isinstance(err["error"], dict) and err["error"].get("code")):
                    failures.append(f"[FAIL] {label}: structured error on stderr missing ok=false/error.code{verb}")
            except ValueError:
                pass  # human-mode stderr is allowed to be plain text
            print(f"[PASS] {label}: exit {proc.returncode}, error surfaced on stderr")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("binary", help="path to the built CLI binary")
    ap.add_argument("commands", nargs="*", help="subcommands to probe")
    ap.add_argument("--module", metavar="DIR", help="Go module dir: also run go vet/test")
    ap.add_argument("--verbose", action="store_true", help="print captured output on failures")
    args = ap.parse_args()

    binary = str(Path(args.binary).resolve())
    if not Path(binary).exists():
        print(f"[FAIL] binary not found: {binary}")
        return 1

    failures: list[str] = []

    # --- help / version / usage scaffolding --------------------------------
    for probe, expect_json in [(["--help"], False), (["--version"], False), (["help"], False)]:
        p = run(binary, probe)
        if p.returncode != 0 or not p.stdout.strip() or p.stderr.strip():
            failures.append(f"[FAIL] %s: expected exit 0 with stdout and empty stderr (got {p.returncode})" % " ".join(probe))
        else:
            print(f"[PASS] {' '.join(probe)}")

    # Usage errors must exit 2 with a message on stderr and empty stdout.
    p = run(binary, ["--definitely-not-a-real-flag"])
    if p.returncode != 2 or not p.stderr.strip() or p.stdout.strip():
        if args.verbose:
            failures.append(f"[FAIL] bad-flag probe: expected exit 2 + stderr, got {p.returncode} (out={p.stdout!r}, err={p.stderr!r})")
        else:
            failures.append(f"[FAIL] bad-flag probe: expected exit 2 + stderr, got {p.returncode}")
    else:
        print("[PASS] bad-flag probe: exit 2, error on stderr")

    # --- per-command probes -------------------------------------------------
    for cmd in args.commands:
        kw = cmd.split(" ")
        plain = run(binary, kw)
        checks(failures, args.verbose, f"{cmd} (plain)", plain, expect_json_success=False)
        j = run(binary, kw + ["--json"])
        checks(failures, args.verbose, f"{cmd} --json", j, expect_json_success=True)
        nc = run(binary, kw + ["--json"], env_extra={"NO_COLOR": "1"})
        checks(failures, args.verbose, f"{cmd} --json NO_COLOR=1", nc, expect_json_success=True)

    # --- go quality gates ---------------------------------------------------
    if args.module:
        mod = Path(args.module).resolve()
        for gate, argv in [("go vet", ["vet", "./..."]), ("go test", ["test", "./..."])]:
            p = subprocess.run(["go", *argv], cwd=mod, capture_output=True, timeout=300)
            if p.returncode != 0:
                if args.verbose:
                    failures.append(f"[FAIL] {gate}: exit {p.returncode} (err={p.stderr.decode()!r})")
                else:
                    failures.append(f"[FAIL] {gate}: exit {p.returncode}")
            else:
                print(f"[PASS] {gate} ./...")

    if failures:
        print(f"\n{len(failures)} failure(s):")
        for f in failures:
            print(f"  {f}")
        return 1

    print("\nAll checks passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())