import hashlib
import importlib.util
import tempfile
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
SCRIPT_PATH = REPO_ROOT / ".github" / "scripts" / "select_release_assets.py"


def load_script():
    spec = importlib.util.spec_from_file_location("select_release_assets", SCRIPT_PATH)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Could not load {SCRIPT_PATH}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class SelectReleaseAssetsTests(unittest.TestCase):
    def setUp(self) -> None:
        self.module = load_script()
        self.temp_dir = tempfile.TemporaryDirectory()
        self.root = Path(self.temp_dir.name)
        self.local = self.root / "release-assets"
        self.published = self.root / "published-checksums"
        self.upload = self.root / "upload-assets"
        self.local.mkdir()
        self.published.mkdir()

    def tearDown(self) -> None:
        self.temp_dir.cleanup()

    def write_asset(self, name: str, content: bytes) -> str:
        digest = hashlib.sha256(content).hexdigest()
        (self.local / name).write_bytes(content)
        (self.local / f"{name}.sha256").write_text(
            f"{digest}  {name}\n", encoding="utf-8"
        )
        return digest

    def write_published_checksum(self, name: str, digest: str) -> None:
        (self.published / f"{name}.sha256").write_text(
            f"{digest}  {name}\n", encoding="utf-8"
        )

    def test_skips_asset_when_archive_and_checksum_match(self) -> None:
        name = "morphir-1.2.3-x86_64-unknown-linux-gnu.tgz"
        digest = self.write_asset(name, b"same artifact")
        self.write_published_checksum(name, digest)

        selected = self.module.select_release_assets(
            self.local,
            self.published,
            {name, f"{name}.sha256"},
            self.upload,
        )

        self.assertEqual([], selected)

    def test_selects_asset_when_published_hash_differs(self) -> None:
        name = "morphir-1.2.3-aarch64-apple-darwin.tgz"
        self.write_asset(name, b"new artifact")
        self.write_published_checksum(name, "0" * 64)

        selected = self.module.select_release_assets(
            self.local,
            self.published,
            {name, f"{name}.sha256"},
            self.upload,
        )

        self.assertEqual([name, f"{name}.sha256"], selected)
        self.assertTrue((self.upload / name).is_file())
        self.assertTrue((self.upload / f"{name}.sha256").is_file())

    def test_selects_asset_when_published_archive_is_missing(self) -> None:
        name = "morphir-1.2.3-aarch64-pc-windows-msvc.zip"
        digest = self.write_asset(name, b"windows artifact")
        self.write_published_checksum(name, digest)

        selected = self.module.select_release_assets(
            self.local,
            self.published,
            {f"{name}.sha256"},
            self.upload,
        )

        self.assertEqual([name, f"{name}.sha256"], selected)

    def test_rejects_local_archive_with_incorrect_checksum(self) -> None:
        name = "morphir-1.2.3-x86_64-unknown-linux-gnu.tgz"
        self.write_asset(name, b"cli artifact")
        (self.local / f"{name}.sha256").write_text(
            f"{'0' * 64}  {name}\n", encoding="utf-8"
        )

        with self.assertRaisesRegex(ValueError, "does not match"):
            self.module.select_release_assets(
                self.local,
                self.published,
                set(),
                self.upload,
            )


if __name__ == "__main__":
    unittest.main()
