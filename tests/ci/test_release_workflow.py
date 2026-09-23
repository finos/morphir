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
    def test_package_acceptance_baselines_trigger_cli_tests(self) -> None:
        rust_filter = self.ci_workflow.split("            rust:\n", 1)[1].split(
            "            rust-conformance:\n", 1
        )[0]
        self.assertIn("- 'spec/mck/baseline/package/**'", rust_filter)
        cli_job = self.ci_workflow.split("    name: morphir CLI (test + integration)", 1)[1].split(
            "\n  check-cli-docs:", 1
        )[0]
        self.assertIn("needs.changes.outputs.rust == 'true'", cli_job)
        self.assertIn("cargo test --locked --package morphir", cli_job)

    def test_linux_offline_evidence_is_readable_by_the_artifact_uploader(self) -> None:
        workflow = (REPO_ROOT / ".github/workflows/mck-release-acceptance.yml").read_text()
        self.assertIn("name: Restore Linux evidence ownership", workflow)
        step = workflow.split("name: Restore Linux evidence ownership", 1)[1].split("\n      - name:", 1)[0]
        self.assertIn("if: always() && runner.os == 'Linux'", step)
        self.assertIn('sudo chown -R "$(id -u):$(id -g)" .dev/out/mck-release-acceptance', step)
        self.assertLess(workflow.index("name: Restore Linux evidence ownership"), workflow.index("name: Retain acceptance evidence"))

    def test_acceptance_automation_can_qualify_an_unchanged_source_tag(self) -> None:
        workflow = (REPO_ROOT / ".github/workflows/mck-release-acceptance.yml").read_text()
        self.assertIn("ref: ${{ github.sha }}", workflow)
        self.assertIn("path: .dev/acceptance-tools", workflow)
        self.assertIn("node .dev/acceptance-tools/tools/mck-release-acceptance.mjs", workflow)
        self.assertIn("ref: ${{ inputs.tag }}", workflow)
        self.assertIn("include-hidden-files: true", workflow)
        self.assertIn("node --test tools/mck-release-version.test.mjs", self.ci_workflow)

    def test_published_acceptance_is_manual_and_checks_all_native_targets(self) -> None:
        path = REPO_ROOT / ".github/workflows/mck-release-acceptance.yml"
        self.assertTrue(path.exists(), "published-release acceptance workflow is missing")
        workflow = path.read_text()
        self.assertIn("workflow_dispatch:", workflow)
        self.assertNotIn("  push:", workflow)
        self.assertIn("ref: ${{ inputs.tag }}", workflow)
        for target in (
            "x86_64-unknown-linux-gnu", "aarch64-unknown-linux-gnu",
            "x86_64-apple-darwin", "aarch64-apple-darwin",
            "x86_64-pc-windows-msvc", "aarch64-pc-windows-msvc",
        ):
            self.assertIn(f"target: {target}", workflow)
        self.assertIn("timeout-minutes: 60", workflow)
        self.assertIn("node .dev/acceptance-tools/tools/mck-release-acceptance.mjs", workflow)
        self.assertIn("unshare --net", workflow)
        self.assertIn("(deny network*)", workflow)
        self.assertIn("New-NetFirewallRule", workflow)
        self.assertIn("Remove-NetFirewallRule", workflow)
        self.assertIn("finally", workflow)
        self.assertIn("RUNNER_ENVIRONMENT", workflow)
        self.assertIn("github-hosted", workflow)
        self.assertIn("MORPHIR_MCK_REQUIRE_NETWORK_DENIAL", workflow)
        self.assertIn("MORPHIR_MCK_PREACQUIRED_KIT", workflow)
        self.assertIn("WaitForExit(600000)", workflow)
        self.assertNotIn("continue-on-error", workflow)
        self.assertIn("- '.github/workflows/mck-release-acceptance.yml'", self.ci_workflow)
        self.assertIn("- 'tools/mck-release-acceptance.mjs'", self.ci_workflow)
        self.assertIn("node --check tools/mck-release-acceptance.mjs", self.ci_workflow)

    def test_published_acceptance_prepares_verified_inputs_before_network_denial(self) -> None:
        prepare = (REPO_ROOT / "tools/mck-release-acceptance.mjs").read_text()
        self.assertIn("https://github.com/finos/morphir/releases/download/", prepare)
        self.assertIn('createHash("sha256")', prepare)
        self.assertIn("published CLI archive checksum mismatch", prepare)
        self.assertIn('"--no-run", "--message-format=json-render-diagnostics"', prepare)
        self.assertIn('entry.target.name === "mck_run" && entry.executable', prepare)
        self.assertIn('sourceQualificationTargets(metadata)', prepare)
        self.assertIn('"metadata", "--locked", "--no-deps", "--format-version", "1"', prepare)
        self.assertIn('...qualificationTargets.flatMap(name => ["--test", name])', prepare)
        self.assertIn("tools/mck-release-qualification.test.mjs", self.ci_workflow)
        self.assertIn("- 'tools/mck-release-qualification*.mjs'", self.ci_workflow)
        self.assertIn('source-transport.log', prepare)
        self.assertIn('"--source", "github:finos/morphir", "--revision", commit', prepare)
        self.assertIn('run("git", ["rev-parse", `${tag}^{commit}`]) !== commit', prepare)
        self.assertIn('"kit/** -text\\n"', prepare)
        self.assertIn('"commit", "-m", "Record exact-commit acquired kit"', prepare)
        self.assertIn('network probe unavailable before isolation', prepare)
        self.assertLess(prepare.index('await rm(acquisition,'), prepare.index('const environment ='))
        self.assertIn('MORPHIR_MCK_PREACQUIRED_KIT: kit', prepare)
        runtime = (REPO_ROOT / "crates/morphir/tests/mck_run.rs").read_text()
        self.assertIn('copy the pre-acquired kit', runtime)
        self.assertIn('network isolation unavailable: direct outbound TCP succeeded', runtime)
        self.assertIn('actual["kit"]["snapshotDigest"]', runtime)
        self.assertIn('without_volatile(expected)["records"]', runtime)

    def test_package_mvp_acceptance_uses_published_binary_with_prepared_native_adapter(self) -> None:
        workflow = (REPO_ROOT / ".github/workflows/mck-release-acceptance.yml").read_text()
        prepare = (REPO_ROOT / "tools/mck-release-acceptance.mjs").read_text()
        runtime = (REPO_ROOT / "crates/morphir/tests/mck_run.rs").read_text()
        self.assertIn('entry.name === "mck_package_mvp"', prepare)
        self.assertIn('"--package", "morphir-mck-adapter"', prepare)
        self.assertIn('MORPHIR_MCK_MVP_REQUIRED: "1"', prepare)
        self.assertIn('MORPHIR_MCK_MVP_ADAPTER: mvpAdapter', prepare)
        self.assertIn('MORPHIR_MCK_MVP_ADAPTER="${MORPHIR_MCK_MVP_ADAPTER:-}"', workflow)
        self.assertIn('mvp_acceptance::qualify(work.path(), &run', runtime)
        self.assertIn('"package-mvp.json"', runtime)
        self.assertIn('"package-examples.log"', runtime)

    @classmethod
    def setUpClass(cls) -> None:
        cls.workflow = WORKFLOW_PATH.read_text(encoding="utf-8")
        cls.ci_workflow = CI_WORKFLOW_PATH.read_text(encoding="utf-8")
        cls.cargo_toml = CARGO_TOML_PATH.read_text(encoding="utf-8")

    def test_workspace_uses_release_prerelease_version(self) -> None:
        workspace = tomllib.loads(WORKSPACE_TOML_PATH.read_text(encoding="utf-8"))
        self.assertEqual("0.4.0-beta.4", workspace["workspace"]["package"]["version"])

        lockfile = tomllib.loads(CARGO_LOCK_PATH.read_text(encoding="utf-8"))
        workspace_packages = {
            package["name"]: package["version"]
            for package in lockfile["package"]
            if package["name"] in {"morphir", "morphir-mck"}
        }
        self.assertEqual(
            {"morphir": "0.4.0-beta.4", "morphir-mck": "0.4.0-beta.4"},
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

    def test_windows_git_long_paths_are_enabled_before_submodule_checkout(self) -> None:
        acceptance = (REPO_ROOT / ".github/workflows/mck-release-acceptance.yml").read_text()
        for workflow, checkout in (
            (self.workflow.split("  package-cli:", 1)[1], "name: Checkout code"),
            (acceptance.split("  qualify:", 1)[1], "name: Check out the published source tag"),
        ):
            with self.subTest(workflow=workflow.splitlines()[0]):
                self.assertIn("name: Configure Windows Git paths", workflow)
                setup = workflow.split("name: Configure Windows Git paths", 1)[1].split("\n      - name:", 1)[0]
                self.assertIn("if: runner.os == 'Windows'", setup)
                self.assertIn("git config --global core.longpaths true", setup)
                self.assertIn("CARGO_NET_GIT_FETCH_WITH_CLI=true", setup)
                self.assertIn("$env:GITHUB_ENV", setup)
                self.assertLess(workflow.index("name: Configure Windows Git paths"), workflow.index(checkout))

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

    def test_extracted_cli_passes_mck_smoke_before_artifact_upload(self) -> None:
        package_job = self.workflow.split("  package-cli:\n", maxsplit=1)[1]
        package_job = package_job.split("  publish-release:\n", maxsplit=1)[0]
        self.assertIn("tar -xzf", package_job)
        self.assertIn("Expand-Archive", package_job)
        self.assertIn("MORPHIR_MCK_INSTALLED_CLI", package_job)
        self.assertIn("installed_cli_runs_vendored_kit_without_tool_runtimes", package_job)
        self.assertIn("--release --package morphir --target ${{ matrix.target }}", package_job)
        self.assertLess(
            package_job.index("name: Verify packaged MCK CLI"),
            package_job.index("name: Upload CLI artifact"),
        )

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
            "needs: [changes, lint, morphir-cli-test, check-cli-docs, docs, rust-conformance, release-workflow, desktop-demo, package-mck]",
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
