#!/usr/bin/env python3
"""Download the pinned published extension bundles and verify their checksums."""

from __future__ import annotations

import hashlib
import sys
import tomllib
import urllib.request
from pathlib import Path

REPOSITORY_ROOT = Path(__file__).resolve().parents[4]
PINS_PATH = REPOSITORY_ROOT / ".config" / "published-extension-bundles.toml"
RELEASES = "https://github.com/finos/morphir-rust/releases/download"


def asset_urls(tag: str, artifact: str) -> dict[str, str]:
    """Map each bundle role to the release asset that fills it."""
    base = f"{RELEASES}/{tag}/{artifact}"
    return {
        "guest.wasm": f"{base}.wasm",
        "guest.wasm.sha256": f"{base}.wasm.sha256",
        "release.json": f"{base}.release.json",
    }


def verify_checksum(guest: Path, checksum_file: str) -> None:
    expected = checksum_file.split()[0].lower()
    actual = hashlib.sha256(guest.read_bytes()).hexdigest()
    if actual != expected:
        raise RuntimeError(f"checksum mismatch for {guest.name}: {actual} is not {expected}")


def download(url: str) -> bytes:
    with urllib.request.urlopen(url, timeout=60) as response:  # noqa: S310 - fixed https host
        return response.read()


def fetch(short_id: str, tag: str, artifact: str, output: Path) -> None:
    """Write the bundle the way `extension repository publish` expects it.

    The directory holds exactly the descriptor named `release.json`, the guest and its checksum.
    """
    bundle = output / short_id
    bundle.mkdir(parents=True, exist_ok=True)
    for stale in bundle.iterdir():
        stale.unlink()
    urls = asset_urls(tag, artifact)
    guest = bundle / f"{artifact}.wasm"
    guest.write_bytes(download(urls["guest.wasm"]))
    checksum = download(urls["guest.wasm.sha256"]).decode("utf-8")
    verify_checksum(guest, checksum)
    (bundle / f"{artifact}.wasm.sha256").write_text(checksum, encoding="utf-8")
    (bundle / "release.json").write_bytes(download(urls["release.json"]))
    print(f"{short_id}: {tag} -> {bundle}")


def main(arguments: list[str]) -> int:
    output = Path(arguments[0]) if arguments else REPOSITORY_ROOT / ".dev" / "out" / "published-bundles"
    pins = tomllib.loads(PINS_PATH.read_text(encoding="utf-8"))["bundles"]
    for short_id, pin in pins.items():
        fetch(short_id, pin["tag"], pin["artifact"], output.resolve())
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
