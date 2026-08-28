import json
import subprocess
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
CURRENT_STABLE_RUST_VERSION = "1.98"


class WorkspaceRustBaselineTests(unittest.TestCase):
    def test_every_workspace_package_uses_current_stable_rust(self) -> None:
        completed = subprocess.run(
            ["cargo", "metadata", "--no-deps", "--format-version", "1"],
            cwd=REPO_ROOT,
            check=True,
            capture_output=True,
            text=True,
        )
        metadata = json.loads(completed.stdout)
        versions = {
            package["name"]: package["rust_version"]
            for package in metadata["packages"]
        }

        self.assertTrue(versions)
        self.assertEqual(
            {},
            {
                name: version
                for name, version in versions.items()
                if version != CURRENT_STABLE_RUST_VERSION
            },
            "every workspace package must inherit the current stable Rust baseline",
        )


if __name__ == "__main__":
    unittest.main()
