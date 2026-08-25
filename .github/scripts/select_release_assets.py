#!/usr/bin/env python3

import argparse
import hashlib
import shutil
from pathlib import Path


def read_checksum(path: Path) -> str:
    fields = path.read_text(encoding="utf-8").split()
    if not fields:
        raise ValueError(f"Checksum file is empty: {path}")

    digest = fields[0].lower()
    if len(digest) != 64 or any(char not in "0123456789abcdef" for char in digest):
        raise ValueError(f"Checksum file does not contain a SHA-256 hash: {path}")
    return digest


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def select_release_assets(
    release_assets: Path,
    published_checksums: Path,
    published_assets: set[str],
    upload_dir: Path,
) -> list[str]:
    checksum_files = sorted(release_assets.glob("*.sha256"))
    if not checksum_files:
        raise ValueError(f"No checksum files found in {release_assets}")

    archives = sorted(
        path
        for path in release_assets.iterdir()
        if path.is_file() and path.suffix != ".sha256"
    )
    missing_checksums = [
        archive.name
        for archive in archives
        if not (release_assets / f"{archive.name}.sha256").is_file()
    ]
    if missing_checksums:
        raise ValueError(
            "Release assets are missing checksums: " + ", ".join(missing_checksums)
        )

    selected: list[str] = []
    for checksum_file in checksum_files:
        archive_name = checksum_file.name.removesuffix(".sha256")
        archive = release_assets / archive_name
        if not archive.is_file():
            raise ValueError(f"Checksum has no matching release asset: {checksum_file.name}")

        declared_hash = read_checksum(checksum_file)
        actual_hash = sha256(archive)
        if declared_hash != actual_hash:
            raise ValueError(
                f"Checksum for {archive_name} does not match the packaged artifact"
            )

        published_checksum = published_checksums / checksum_file.name
        published_hash = None
        if published_checksum.is_file():
            try:
                published_hash = read_checksum(published_checksum)
            except ValueError:
                published_hash = None

        published_pair_exists = (
            archive_name in published_assets and checksum_file.name in published_assets
        )
        if published_pair_exists and published_hash == actual_hash:
            print(f"Skipping unchanged release asset: {archive_name}")
            continue

        upload_dir.mkdir(parents=True, exist_ok=True)
        shutil.copy2(archive, upload_dir / archive.name)
        shutil.copy2(checksum_file, upload_dir / checksum_file.name)
        selected.extend([archive.name, checksum_file.name])
        print(f"Selected release asset for upload: {archive_name}")

    return selected


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Select release artifacts whose published SHA-256 hash changed."
    )
    parser.add_argument("--release-assets", type=Path, required=True)
    parser.add_argument("--published-checksums", type=Path, required=True)
    parser.add_argument("--published-assets", type=Path, required=True)
    parser.add_argument("--upload-dir", type=Path, required=True)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    published_assets = (
        set(args.published_assets.read_text(encoding="utf-8").splitlines())
        if args.published_assets.is_file()
        else set()
    )
    select_release_assets(
        args.release_assets,
        args.published_checksums,
        published_assets,
        args.upload_dir,
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
