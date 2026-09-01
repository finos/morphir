import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
CI_WORKFLOW_PATH = REPO_ROOT / ".github" / "workflows" / "ci.yml"
RELEASE_WORKFLOW_PATH = REPO_ROOT / ".github" / "workflows" / "release.yml"
SETUP_RUST_CI_ACTION = REPO_ROOT / ".github" / "actions" / "setup-rust-ci" / "action.yml"
CACHE_SCALA_NATIVE_IMAGE_ACTION = (
    REPO_ROOT / ".github" / "actions" / "cache-scala-native-image" / "action.yml"
)


class CiRustOptimizationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.ci_workflow = CI_WORKFLOW_PATH.read_text(encoding="utf-8")
        cls.release_workflow = RELEASE_WORKFLOW_PATH.read_text(encoding="utf-8")
        cls.setup_rust_ci_action = SETUP_RUST_CI_ACTION.read_text(encoding="utf-8")
        cls.cache_scala_native_image_action = CACHE_SCALA_NATIVE_IMAGE_ACTION.read_text(
            encoding="utf-8"
        )
        cls.scala_build_job = cls.ci_workflow.split(
            "  build-scala-extension:\n", maxsplit=1
        )[1].split("  morphir-cli-test:\n", maxsplit=1)[0]

    def test_ci_enables_sccache(self) -> None:
        self.assertIn('SCCACHE_GHA_ENABLED: "true"', self.ci_workflow)
        self.assertIn("RUSTC_WRAPPER: sccache", self.ci_workflow)

    def test_rust_jobs_use_shared_setup_action(self) -> None:
        self.assertEqual(
            self.ci_workflow.count("uses: ./.github/actions/setup-rust-ci"),
            3,
        )

    def test_setup_rust_ci_action_shares_cargo_cache(self) -> None:
        self.assertIn("mozilla-actions/sccache-action@v0.0.10", self.setup_rust_ci_action)
        self.assertIn("shared-key: ${{ inputs.shared-key }}", self.setup_rust_ci_action)
        self.assertIn("add-job-id-key: false", self.setup_rust_ci_action)
        self.assertIn("cache-on-failure: true", self.setup_rust_ci_action)
        self.assertIn("default: morphir-rust", self.setup_rust_ci_action)
        self.assertIn("link-arg=-fuse-ld=mold", self.setup_rust_ci_action)

    def test_scala_build_caches_native_image_output(self) -> None:
        self.assertIn(
            "uses: ./.github/actions/cache-scala-native-image", self.scala_build_job
        )
        self.assertIn("git rev-parse", self.cache_scala_native_image_action)
        self.assertIn("/out", self.cache_scala_native_image_action)

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


if __name__ == "__main__":
    unittest.main()
