"""The CLI is tested against the extension bundles users can install."""

from __future__ import annotations

import hashlib
import importlib.util
import tempfile
import tomllib
import unittest
from pathlib import Path

REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
PINS_PATH = REPOSITORY_ROOT / ".config" / "published-extension-bundles.toml"
SCRIPT_PATH = REPOSITORY_ROOT / ".config" / "mise" / "tasks" / "ci" / "fetch_published_bundles.py"
CI_WORKFLOW_PATH = REPOSITORY_ROOT / ".github" / "workflows" / "ci.yml"


def load_script():
    spec = importlib.util.spec_from_file_location("fetch_published_bundles", SCRIPT_PATH)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class PublishedExtensionBundleTests(unittest.TestCase):
    def test_every_pin_names_a_release_tag_and_its_artifact(self) -> None:
        pins = tomllib.loads(PINS_PATH.read_text(encoding="utf-8"))["bundles"]
        self.assertEqual({"avro", "openapi", "python", "rust"}, set(pins))
        for short_id, pin in pins.items():
            self.assertRegex(pin["tag"], rf"^extension/{short_id}/v\d+\.\d+\.\d+$")
            version = pin["tag"].rsplit("/v", 1)[1]
            self.assertTrue(pin["artifact"].endswith(f"-{version}"), pin)

    def test_assets_are_the_guest_its_checksum_and_the_descriptor(self) -> None:
        script = load_script()
        urls = script.asset_urls("extension/avro/v0.1.1", "morphir-avro-extension-0.1.1")
        base = "https://github.com/finos/morphir-rust/releases/download/extension/avro/v0.1.1/"
        self.assertEqual(
            {
                "guest.wasm": base + "morphir-avro-extension-0.1.1.wasm",
                "guest.wasm.sha256": base + "morphir-avro-extension-0.1.1.wasm.sha256",
                "release.json": base + "morphir-avro-extension-0.1.1.release.json",
            },
            {role: url for role, url in urls.items()},
        )

    def test_a_guest_that_does_not_match_its_checksum_is_refused(self) -> None:
        script = load_script()
        with tempfile.TemporaryDirectory() as directory:
            guest = Path(directory) / "guest.wasm"
            guest.write_bytes(b"guest")
            digest = hashlib.sha256(b"guest").hexdigest()
            script.verify_checksum(guest, f"{digest}  guest.wasm\n")
            with self.assertRaisesRegex(RuntimeError, "checksum"):
                script.verify_checksum(guest, f"{'0' * 64}  guest.wasm\n")

    def test_ci_tests_published_bundles_and_builds_no_wasm_guest(self) -> None:
        workflow = CI_WORKFLOW_PATH.read_text(encoding="utf-8")
        self.assertIn("mise run ci:fetch-published-bundles", workflow)
        # Moving a pin is a change to what the CLI is tested against, so it runs the Rust jobs.
        self.assertIn("              - '.config/published-extension-bundles.toml'\n", workflow)
        self.assertNotIn("--target wasm32-unknown-unknown", workflow)
        self.assertNotIn("package_extension.py", workflow)
        for test in (
            "generate_extension",
            "generate_openapi_extension",
            "python_extension",
            "rust_extension",
        ):
            self.assertIn(f"--test {test}", workflow)


if __name__ == "__main__":
    unittest.main()
