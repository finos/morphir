import tomllib
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
WORKFLOW_PATH = REPO_ROOT / ".github" / "workflows" / "release.yml"
CARGO_TOML_PATH = REPO_ROOT / "crates" / "morphir" / "Cargo.toml"
WORKSPACE_TOML_PATH = REPO_ROOT / "Cargo.toml"
CARGO_LOCK_PATH = REPO_ROOT / "Cargo.lock"


class ReleaseWorkflowTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.workflow = WORKFLOW_PATH.read_text(encoding="utf-8")
        cls.cargo_toml = CARGO_TOML_PATH.read_text(encoding="utf-8")

    def test_workspace_uses_release_prerelease_version(self) -> None:
        workspace = tomllib.loads(WORKSPACE_TOML_PATH.read_text(encoding="utf-8"))
        self.assertEqual("0.2.0-alpha-01", workspace["workspace"]["package"]["version"])

        lockfile = tomllib.loads(CARGO_LOCK_PATH.read_text(encoding="utf-8"))
        workspace_packages = {
            package["name"]: package["version"]
            for package in lockfile["package"]
            if package["name"] in {"morphir", "morphir-live"}
        }
        self.assertEqual(
            {
                "morphir": "0.2.0-alpha-01",
                "morphir-live": "0.2.0-alpha-01",
            },
            workspace_packages,
        )

    def test_manual_release_checks_out_requested_tag(self) -> None:
        self.assertIn("release-info:", self.workflow)
        self.assertIn(
            "ref: ${{ github.event_name == 'workflow_dispatch' "
            "&& inputs.tag || github.ref }}",
            self.workflow,
        )
        self.assertIn("ref: ${{ needs.release-info.outputs.tag }}", self.workflow)

    def test_release_tag_matches_workspace_version(self) -> None:
        self.assertIn("Validate release tag", self.workflow)
        self.assertIn('EXPECTED_TAG="v${VERSION}"', self.workflow)
        self.assertIn('if [ "$TAG" != "$EXPECTED_TAG" ]; then', self.workflow)

    def test_cli_build_covers_supported_targets(self) -> None:
        targets = {
            "x86_64-unknown-linux-gnu",
            "aarch64-unknown-linux-gnu",
            "x86_64-apple-darwin",
            "aarch64-apple-darwin",
            "x86_64-pc-windows-msvc",
            "aarch64-pc-windows-msvc",
        }

        self.assertIn("package-cli:", self.workflow)
        self.assertIn("name: Package Morphir CLI (${{ matrix.target }})", self.workflow)
        self.assertIn("fail-fast: false", self.workflow)
        for target in targets:
            self.assertIn(f"target: {target}", self.workflow)

    def test_cli_archives_match_cargo_binstall_metadata(self) -> None:
        self.assertIn(
            'pkg-url = "{ repo }/releases/download/v{ version }/'
            '{ name }-{ version }-{ target }.{ archive-format }"',
            self.cargo_toml,
        )
        self.assertIn(
            'ARCHIVE="morphir-${{ needs.release-info.outputs.version }}-'
            '${{ matrix.target }}.${{ matrix.archive }}"',
            self.workflow,
        )
        self.assertIn(
            '$archive = "morphir-${{ needs.release-info.outputs.version }}-'
            '${{ matrix.target }}.${{ matrix.archive }}"',
            self.workflow,
        )

    def test_packaging_jobs_support_independent_retries(self) -> None:
        self.assertIn("name: morphir-cli-${{ matrix.target }}", self.workflow)
        self.assertIn("overwrite: true", self.workflow)
        self.assertIn("retention-days: 7", self.workflow)

    def test_publish_job_only_collects_release_artifacts(self) -> None:
        self.assertRegex(
            self.workflow,
            r"publish-release:\n(?:.|\n)*?needs: "
            r"\[release-info, package-live, package-cli\]",
        )
        self.assertIn("merge-multiple: true", self.workflow)

        publish_job = self.workflow.split("  publish-release:\n", maxsplit=1)[1]
        publish_job = publish_job.split("\n  deploy-pages:\n", maxsplit=1)[0]
        self.assertIn("permissions:\n      contents: write", publish_job)
        self.assertNotIn("cargo build", publish_job)
        self.assertNotIn("dx build", publish_job)

    def test_publish_job_skips_artifacts_with_matching_hashes(self) -> None:
        publish_job = self.workflow.split("  publish-release:\n", maxsplit=1)[1]
        publish_job = publish_job.split("\n  deploy-pages:\n", maxsplit=1)[0]

        self.assertIn('gh release view "$TAG"', publish_job)
        self.assertIn('gh release download "$TAG"', publish_job)
        self.assertIn("select_release_assets.py", publish_job)
        self.assertIn('gh release upload "$TAG"', publish_job)
        self.assertIn("--clobber", publish_job)
        self.assertNotIn("softprops/action-gh-release", publish_job)

    def test_pages_deployment_reuses_packaged_live_artifact(self) -> None:
        pages_job = self.workflow.split("  deploy-pages:\n", maxsplit=1)[1]
        self.assertIn("name: morphir-live-wasm", pages_job)
        self.assertIn("tar -xzf morphir-live-*.tar.gz -C pages-dist", pages_job)
        self.assertNotIn("dx build", pages_job)


if __name__ == "__main__":
    unittest.main()
