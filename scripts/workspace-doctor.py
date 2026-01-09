#!/usr/bin/env python3
"""
Diagnose Go workspace issues and offer local fixes.
"""
from __future__ import annotations

import argparse
import os
import re
import subprocess
import sys
from pathlib import Path


def run(cmd: list[str], cwd: Path | None = None, check: bool = True) -> subprocess.CompletedProcess[str]:
    return subprocess.run(cmd, cwd=cwd, check=check, text=True, capture_output=True)


def run_lines(cmd: list[str], cwd: Path | None = None) -> list[str]:
    result = run(cmd, cwd=cwd, check=False)
    if result.returncode != 0:
        return []
    return [line for line in result.stdout.splitlines() if line.strip()]


def read_go_env(key: str, cwd: Path) -> str:
    result = run(["go", "env", key], cwd=cwd, check=False)
    return result.stdout.strip()


def find_go_mods(root: Path) -> list[Path]:
    mods: list[Path] = []
    for path in root.rglob("go.mod"):
        if "vendor" in path.parts or "node_modules" in path.parts:
            continue
        mods.append(path)
    return sorted(mods)


def parse_go_work_use(go_work_path: Path) -> list[str]:
    if not go_work_path.exists():
        return []
    entries: list[str] = []
    in_use = False
    for line in go_work_path.read_text().splitlines():
        line = line.strip()
        if line.startswith("use ("):
            in_use = True
            continue
        if line == ")":
            in_use = False
            continue
        if in_use and line:
            entries.append(line)
    return entries


def has_replace_in_go_mod(root: Path) -> bool:
    for mod_file in find_go_mods(root):
        for line in mod_file.read_text().splitlines():
            if line.lstrip().startswith("replace "):
                return True
    return False


def is_go_work_staged(root: Path) -> bool:
    result = run(["git", "status", "--short"], cwd=root, check=False)
    return "go.work" in result.stdout


def list_git_tags(root: Path, pattern: str) -> list[str]:
    return run_lines(["git", "tag", "-l", pattern], cwd=root)


def go_work_has_replace(root: Path, module: str, version: str) -> bool:
    go_work = root / "go.work"
    if not go_work.exists():
        return False
    needle = f"{module} {version} =>"
    return needle in go_work.read_text()


def prompt_choice() -> str:
    if not sys.stdin.isatty():
        return "replace"
    print("")
    print("Choose a fix for missing tags:")
    print("  [r] replace  (default) add versioned go.work replaces")
    print("  [t] tags     create local-only tags")
    print("  [n] none     no automatic fixes")
    choice = input("Select fix [r/t/n]: ").strip().lower()
    if choice == "t":
        return "tags"
    if choice == "n":
        return "none"
    return "replace"


def prompt_yes_no(message: str, default_yes: bool = True) -> bool:
    if not sys.stdin.isatty():
        return default_yes
    suffix = "[Y/n]" if default_yes else "[y/N]"
    choice = input(f"{message} {suffix}: ").strip().lower()
    if not choice:
        return default_yes
    return choice in {"y", "yes"}


def main() -> int:
    parser = argparse.ArgumentParser(description="Diagnose Go workspace issues and offer local fixes.")
    parser.add_argument("--fix", choices=["replace", "tags", "none", "prompt"], default="prompt")
    args = parser.parse_args()

    script_dir = Path(__file__).resolve().parent
    root = script_dir.parent
    os.chdir(root)

    print(f"Workspace doctor running in: {root}")

    issues = 0

    gowork = read_go_env("GOWORK", root)
    gomod = read_go_env("GOMOD", root)

    if not gowork or gowork == "off":
        print("WARN: GOWORK is not set (go env GOWORK is empty or off)")
        issues += 1
    elif Path(gowork) != (root / "go.work"):
        print(f"WARN: GOWORK points elsewhere: {gowork}")
        issues += 1

    if gomod and gomod != "/dev/null":
        print(f"WARN: GOMOD is {gomod} (workspace mode usually sets GOMOD=/dev/null from repo root)")
        issues += 1

    if not (root / "go.work").exists():
        print("WARN: go.work is missing (run: mise run setup-workspace)")
        issues += 1

    if has_replace_in_go_mod(root):
        print("WARN: Found replace directives in go.mod files (remove them and use go.work)")
        issues += 1
    else:
        print("OK: No replace directives in go.mod files")

    if is_go_work_staged(root):
        print("WARN: go.work or go.work.sum is staged (do not commit workspace files)")
        issues += 1
    else:
        print("OK: go.work files are not staged")

    missing_tags: list[dict[str, str]] = []
    mod_files = find_go_mods(root)
    tag_pattern = re.compile(r"^github.com/finos/morphir/(\S+)\s+(v\S+)")

    for mod_file in mod_files:
        for line in mod_file.read_text().splitlines():
            match = tag_pattern.search(line)
            if not match:
                continue
            module_path, version = match.group(1), match.group(2)
            module = f"github.com/finos/morphir/{module_path}"
            tag = f"{module_path}/{version}"
            if list_git_tags(root, tag):
                continue
            local_path = root / module_path
            print(f"WARN: Missing tag for {module} ({version}) -> expected tag {tag}")
            missing_tags.append(
                {
                    "module": module,
                    "version": version,
                    "path": module_path,
                    "tag": tag,
                    "has_path": "yes" if local_path.exists() else "no",
                }
            )

    if missing_tags:
        issues += 1
    else:
        print("OK: All internal module version tags found")

    missing_use: list[str] = []
    go_work = root / "go.work"
    if go_work.exists():
        workspace_use = parse_go_work_use(go_work)
        for mod_file in mod_files:
            rel_dir = os.path.relpath(mod_file.parent, root)
            if not any(entry in {f"./{rel_dir}", rel_dir} for entry in workspace_use):
                print(f"WARN: Module missing from go.work use: {rel_dir}")
                missing_use.append(rel_dir)
                issues += 1

    if issues == 0:
        print("OK: Workspace looks healthy.")
        return 0

    fix_choice = args.fix
    if fix_choice == "prompt":
        fix_choice = prompt_choice()

    if missing_use and go_work.exists():
        if prompt_yes_no("Add missing modules to go.work use?", default_yes=True):
            for rel_dir in missing_use:
                print(f"-> go work use ./{rel_dir}")
                run(["go", "work", "use", f"./{rel_dir}"], cwd=root, check=True)

    if missing_tags:
        if fix_choice == "replace":
            if not go_work.exists():
                print("WARN: go.work is missing; running setup-workspace before applying fixes.")
                run([str(root / "scripts" / "setup-workspace.sh")], cwd=root, check=True)
            for entry in missing_tags:
                if entry["has_path"] != "yes":
                    print(f"WARN: Cannot add replace for {entry['module']}; local path ./{entry['path']} not found")
                    continue
                if go_work_has_replace(root, entry["module"], entry["version"]):
                    print(f"OK: Replace already exists for {entry['module']} {entry['version']}")
                    continue
                replace_arg = f"{entry['module']}@{entry['version']}=./{entry['path']}"
                print(f"-> go work edit -replace={replace_arg}")
                run(["go", "work", "edit", f"-replace={replace_arg}"], cwd=root, check=True)
        elif fix_choice == "tags":
            print("WARN: Creating local-only tags (do not push these)")
            for entry in missing_tags:
                if list_git_tags(root, entry["tag"]):
                    print(f"OK: Tag already exists: {entry['tag']}")
                    continue
                print(f"-> git tag {entry['tag']}")
                run(["git", "tag", entry["tag"]], cwd=root, check=True)
        else:
            print("No automatic fixes applied.")

    print("")
    print("Workspace doctor completed. Re-run your command and verify.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
