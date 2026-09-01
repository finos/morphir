import tomllib
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
WORKFLOW_PATH = REPO_ROOT / ".github" / "workflows" / "release.yml"
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
            {"morphir": "0.4.0-alpha.5"},
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

    def test_release_pipeline_packages_only_the_cli(self) -> None:
        self.assertNotIn("package-live:", self.workflow)
        self.assertNotIn("dioxus-cli", self.workflow)
        self.assertNotIn("morphir-live", self.workflow)

    def test_release_download_selects_cli_artifacts(self) -> None:
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
        self.assertNotIn("deploy-release-pages.yml", release_filter)
        self.assertIn("- 'Cargo.toml'", release_filter)
        self.assertIn("- 'Cargo.lock'", release_filter)

    def test_publish_job_only_collects_release_artifacts(self) -> None:
        self.assertRegex(
            self.workflow,
            r"publish-release:\n(?:.|\n)*?needs: "
            r"\[release-info, package-cli\]",
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

    def test_ci_requires_only_the_cli_rust_job(self) -> None:
        self.assertNotIn("\n  morphir-live:\n", self.ci_workflow)
        # Parallelized Rust jobs: lint + two extension builds + test job feed into check
        self.assertIn(
            "needs: [changes, lint, build-elm-extension, build-scala-extension, morphir-cli-test, check-cli-docs, docs, release-workflow]",
            self.ci_workflow,
        )
        self.assertNotIn(
            "needs: [changes, morphir-cli, docs, release-workflow]",
            self.ci_workflow,
        )

    def test_cli_docs_job_runs_in_parallel_with_integration_tests(self) -> None:
        cli_docs_job = self.ci_workflow.split(
            "  check-cli-docs:\n", maxsplit=1
        )[1].split("  docs:\n", maxsplit=1)[0]
        cli_test_job = self.ci_workflow.split(
            "  morphir-cli-test:\n", maxsplit=1
        )[1].split("  check-cli-docs:\n", maxsplit=1)[0]

        self.assertIn("needs: changes", cli_docs_job)
        self.assertNotIn("needs: [changes, lint", cli_docs_job)
        self.assertIn("mise run docs:cli", cli_docs_job)
        self.assertIn("git status --porcelain --ignored=matching", cli_docs_job)
        self.assertNotIn("Generate CLI docs", cli_test_job)
        self.assertNotIn("Check CLI docs are up to date", cli_test_job)


if __name__ == "__main__":
    unittest.main()
