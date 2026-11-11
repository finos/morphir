import tomllib
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
CI_WORKFLOW_PATH = REPO_ROOT / ".github" / "workflows" / "ci.yml"
WORKSPACE_TOML_PATH = REPO_ROOT / "Cargo.toml"
CARGO_LOCK_PATH = REPO_ROOT / "Cargo.lock"
MCK_RUN_PATH = REPO_ROOT / "crates" / "morphir-mck-cli" / "tests" / "mck_run.rs"


# The official CLI release (.github/workflows/release.yml) is tested in
# tools/cli-release.test.ts. These tests cover the historical acceptance of
# released Rust CLI tags (mck-release-acceptance.yml) and the CI gate.
class ReleaseWorkflowTests(unittest.TestCase):
    def test_package_acceptance_baselines_trigger_runner_tests(self) -> None:
        rust_filter = self.ci_workflow.split("            rust:\n", 1)[1].split(
            "            rust-conformance:\n", 1
        )[0]
        self.assertIn("- 'spec/mck/baseline/package/**'", rust_filter)
        job = self.ci_workflow.split("    name: Rust development tools (test)", 1)[1].split(
            "\n  docs:", 1
        )[0]
        self.assertIn("needs.changes.outputs.rust == 'true'", job)
        self.assertIn("cargo test --locked --package morphir-mck-cli", job)
        self.assertIn("cargo test --locked --package morphir-dev-tools", job)
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
        runtime = MCK_RUN_PATH.read_text()
        self.assertIn('copy the pre-acquired kit', runtime)
        self.assertIn('network isolation unavailable: direct outbound TCP succeeded', runtime)
        self.assertIn('actual["kit"]["snapshotDigest"]', runtime)
        self.assertIn('without_volatile(expected)["records"]', runtime)

    def test_package_mvp_acceptance_uses_published_binary_with_prepared_native_adapter(self) -> None:
        workflow = (REPO_ROOT / ".github/workflows/mck-release-acceptance.yml").read_text()
        prepare = (REPO_ROOT / "tools/mck-release-acceptance.mjs").read_text()
        runtime = MCK_RUN_PATH.read_text()
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
        cls.ci_workflow = CI_WORKFLOW_PATH.read_text(encoding="utf-8")

    def test_workspace_uses_release_prerelease_version(self) -> None:
        workspace = tomllib.loads(WORKSPACE_TOML_PATH.read_text(encoding="utf-8"))
        self.assertEqual("0.4.0-beta.12", workspace["workspace"]["package"]["version"])

        lockfile = tomllib.loads(CARGO_LOCK_PATH.read_text(encoding="utf-8"))
        names = {package["name"] for package in lockfile["package"]}
        self.assertNotIn("morphir", names, "the Rust product CLI was deleted")
        workspace_packages = {
            package["name"]: package["version"]
            for package in lockfile["package"]
            if package["name"] in {"morphir-mck", "morphir-mck-cli", "morphir-dev-tools"}
        }
        self.assertEqual(
            {
                "morphir-mck": "0.4.0-beta.12",
                "morphir-mck-cli": "0.4.0-beta.12",
                "morphir-dev-tools": "0.4.0-beta.12",
            },
            workspace_packages,
        )

    def test_windows_git_long_paths_are_enabled_before_submodule_checkout(self) -> None:
        acceptance = (REPO_ROOT / ".github/workflows/mck-release-acceptance.yml").read_text()
        workflow = acceptance.split("  qualify:", 1)[1]
        self.assertIn("name: Configure Windows Git paths", workflow)
        setup = workflow.split("name: Configure Windows Git paths", 1)[1].split("\n      - name:", 1)[0]
        self.assertIn("if: runner.os == 'Windows'", setup)
        self.assertIn("git config --global core.longpaths true", setup)
        self.assertIn("CARGO_NET_GIT_FETCH_WITH_CLI=true", setup)
        self.assertIn("$env:GITHUB_ENV", setup)
        self.assertLess(
            workflow.index("name: Configure Windows Git paths"),
            workflow.index("name: Check out the published source tag"),
        )

    def test_release_validation_runs_for_the_official_cli_inputs(self) -> None:
        release_filter = self.ci_workflow.split("            release:\n", maxsplit=1)[1]
        release_filter = release_filter.split("\n\n", maxsplit=1)[0]
        for path in (
            "- '.github/workflows/release.yml'",
            "- '.config/cli-release.json'",
            "- 'tools/cli-release*'",
            "- 'ecosystem/morphir-dotnet'",
        ):
            self.assertIn(path, release_filter)
        self.assertNotIn("select_release_assets", release_filter)

    def test_ci_requires_selected_jobs(self) -> None:
        self.assertIn(
            "needs: [changes, lint, rust-dev-tools, docs, rust-conformance, release-workflow, package-mck, toolchain-contracts]",
            self.ci_workflow,
        )
        for retired in ("\n  morphir-cli-test:\n", "\n  library-publish-macos:\n", "\n  check-cli-docs:\n", "\n  desktop-demo:\n"):
            self.assertNotIn(retired, self.ci_workflow)


if __name__ == "__main__":
    unittest.main()