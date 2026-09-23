import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
CI_WORKFLOW_PATH = REPO_ROOT / ".github" / "workflows" / "ci.yml"
RELEASE_WORKFLOW_PATH = REPO_ROOT / ".github" / "workflows" / "release.yml"
SETUP_RUST_CI_ACTION = REPO_ROOT / ".github" / "actions" / "setup-rust-ci" / "action.yml"


class CiRustOptimizationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.ci_workflow = CI_WORKFLOW_PATH.read_text(encoding="utf-8")
        cls.release_workflow = RELEASE_WORKFLOW_PATH.read_text(encoding="utf-8")
        cls.setup_rust_ci_action = SETUP_RUST_CI_ACTION.read_text(encoding="utf-8")

    def test_ci_enables_sccache(self) -> None:
        # mise can compile Cargo tools before the shared setup action runs.
        # A global wrapper points those builds at an executable not installed yet.
        self.assertNotIn("RUSTC_WRAPPER:", self.ci_workflow)
        self.assertIn("echo 'RUSTC_WRAPPER=sccache'", self.setup_rust_ci_action)
        self.assertIn("echo 'SCCACHE_GHA_ENABLED=true'", self.setup_rust_ci_action)
        self.assertLess(
            self.setup_rust_ci_action.index("uses: mozilla-actions/sccache-action"),
            self.setup_rust_ci_action.index("echo 'RUSTC_WRAPPER=sccache'"),
        )

    def test_rust_jobs_use_shared_setup_action(self) -> None:
        self.assertEqual(
            self.ci_workflow.count("uses: ./.github/actions/setup-rust-ci"),
            7,
        )

    def test_setup_rust_ci_action_shares_cargo_cache(self) -> None:
        self.assertIn("inputs.enable-sccache == 'true'", self.setup_rust_ci_action)
        self.assertIn("mozilla-actions/sccache-action@v0.0.11", self.setup_rust_ci_action)
        self.assertIn("shared-key: ${{ inputs.shared-key }}", self.setup_rust_ci_action)
        self.assertIn("add-job-id-key: false", self.setup_rust_ci_action)
        self.assertIn("cache-on-failure: true", self.setup_rust_ci_action)
        self.assertIn("default: morphir-rust", self.setup_rust_ci_action)
        self.assertIn("link-arg=-fuse-ld=mold", self.setup_rust_ci_action)

    def test_ci_tests_published_bundles_and_builds_no_wasm_guest(self) -> None:
        # finos/morphir-rust owns the guest builds. This repository checks that a CLI change
        # does not break the bundles users already installed.
        self.assertIn("mise run ci:fetch-published-bundles", self.ci_workflow)
        self.assertNotIn("--target wasm32-unknown-unknown", self.ci_workflow)
        self.assertNotIn("package_extension.py", self.ci_workflow)
        for test in (
            "generate_extension",
            "generate_openapi_extension",
            "python_extension",
            "rust_extension",
        ):
            self.assertIn(f"--test {test}", self.ci_workflow)
        # Moving a pin changes what the CLI is tested against, so it runs the Rust jobs.
        self.assertIn(
            "              - '.config/published-extension-bundles.toml'\n", self.ci_workflow
        )

    def test_release_package_job_uses_shared_rust_setup(self) -> None:
        package_job = self.release_workflow.split("  package-cli:\n", maxsplit=1)[1].split(
            "  publish-release:\n", maxsplit=1
        )[0]
        self.assertIn("uses: ./.github/actions/setup-rust-ci", package_job)
        self.assertIn(
            "install-mold: ${{ runner.os == 'Linux' }}",
            package_job,
        )
        self.assertIn(
            "shared-key: morphir-release-${{ matrix.target }}",
            package_job,
        )
        self.assertIn(
            "enable-sccache: ${{ runner.arch != 'ARM64' }}",
            package_job,
        )
        self.assertNotIn("SCCACHE_GHA_ENABLED", self.release_workflow)


if __name__ == "__main__":
    unittest.main()
