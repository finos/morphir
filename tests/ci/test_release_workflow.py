import tomllib
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
WORKFLOW_PATH = REPO_ROOT / ".github" / "workflows" / "release.yml"
PAGES_WORKFLOW_PATH = (
    REPO_ROOT / ".github" / "workflows" / "deploy-release-pages.yml"
)
CI_WORKFLOW_PATH = REPO_ROOT / ".github" / "workflows" / "ci.yml"
CARGO_TOML_PATH = REPO_ROOT / "crates" / "morphir" / "Cargo.toml"
WORKSPACE_TOML_PATH = REPO_ROOT / "Cargo.toml"
CARGO_LOCK_PATH = REPO_ROOT / "Cargo.lock"


class ReleaseWorkflowTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.workflow = WORKFLOW_PATH.read_text(encoding="utf-8")
        cls.ci_workflow = CI_WORKFLOW_PATH.read_text(encoding="utf-8")
        cls.cargo_toml = CARGO_TOML_PATH.read_text(encoding="utf-8")

    def test_workspace_uses_release_prerelease_version(self) -> None:
        workspace = tomllib.loads(WORKSPACE_TOML_PATH.read_text(encoding="utf-8"))
        self.assertEqual("0.4.0-alpha.5", workspace["workspace"]["package"]["version"])

        lockfile = tomllib.loads(CARGO_LOCK_PATH.read_text(encoding="utf-8"))
        workspace_packages = {
            package["name"]: package["version"]
            for package in lockfile["package"]
            if package["name"] in {"morphir", "morphir-live"}
        }
        self.assertEqual(
            {
                "morphir": "0.4.0-alpha.5",
                "morphir-live": "0.4.0-alpha.5",
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

    def test_dioxus_cli_install_uses_published_lockfile(self) -> None:
        self.assertIn("cargo install dioxus-cli --locked", self.workflow)

    def test_dioxus_build_selects_package_in_workspace(self) -> None:
        self.assertIn(
            "dx build --release --package morphir-live",
            self.workflow,
        )

    def test_live_archive_uses_dioxus_workspace_output(self) -> None:
        self.assertIn(
            "tar -C target/dx/morphir-live/release/web/public",
            self.workflow,
        )

    def test_release_download_excludes_pages_artifact(self) -> None:
        publish_job = self.workflow.split("  publish-release:\n", maxsplit=1)[1]
        self.assertIn("pattern: morphir-*", publish_job)

    def test_cli_checksum_uses_archive_basename(self) -> None:
        self.assertIn("cd release-assets", self.workflow)
        self.assertIn(
            'shasum -a 256 "$ARCHIVE" > "$ARCHIVE.sha256"',
            self.workflow,
        )
        self.assertNotIn(
            'shasum -a 256 "release-assets/${ARCHIVE}"',
            self.workflow,
        )

    def test_workspace_version_files_trigger_release_validation(self) -> None:
        release_filter = self.ci_workflow.split("            release:\n", maxsplit=1)[1]
        release_filter = release_filter.split("\n\n", maxsplit=1)[0]
        self.assertIn("- '.github/workflows/deploy-release-pages.yml'", release_filter)
        self.assertIn("- 'Cargo.toml'", release_filter)
        self.assertIn("- 'Cargo.lock'", release_filter)

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

    def test_pages_deployment_runs_from_default_branch_after_release(self) -> None:
        pages_workflow = PAGES_WORKFLOW_PATH.read_text(encoding="utf-8")

        self.assertNotIn("\n  deploy-pages:\n", self.workflow)
        self.assertIn("workflows: [Release]", pages_workflow)
        self.assertIn("types: [completed]", pages_workflow)
        self.assertIn("workflow_dispatch:", pages_workflow)
        self.assertIn("run_id:", pages_workflow)
        self.assertIn(
            "github.event.workflow_run.conclusion == 'success'",
            pages_workflow,
        )
        self.assertIn(
            "startsWith(github.event.workflow_run.head_branch, 'v')",
            pages_workflow,
        )
        self.assertIn("name: morphir-live-wasm", pages_workflow)
        self.assertIn("inputs.run_id || github.event.workflow_run.id", pages_workflow)
        self.assertIn("github-token: ${{ secrets.GITHUB_TOKEN }}", pages_workflow)
        self.assertIn(
            "tar -xzf morphir-live-*.tar.gz -C pages-dist",
            pages_workflow,
        )
        self.assertNotIn("dx build", pages_workflow)


if __name__ == "__main__":
    unittest.main()
