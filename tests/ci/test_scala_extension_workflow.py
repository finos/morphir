import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
CI_WORKFLOW_PATH = REPO_ROOT / ".github" / "workflows" / "ci.yml"
PUBLISHED = "${{ github.workspace }}/.dev/out/published-bundles/scala-elm"


class ScalaExtensionWorkflowTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.workflow = CI_WORKFLOW_PATH.read_text(encoding="utf-8")
        cls.rust_filter = cls.workflow.split(
            "            rust:\n", maxsplit=1
        )[1].split("            rust-conformance:\n", maxsplit=1)[0]
        cls.cli_job = cls.workflow.split(
            "  morphir-cli-test:\n", maxsplit=1
        )[1].split("  docs:\n", maxsplit=1)[0]

    def test_scala_provider_comes_from_its_published_release(self) -> None:
        # finos/morphir-scala builds, smoke-tests and releases morphir-scala-elm with its v*
        # release. CI downloads the pinned executable, so it has no GraalVM build and a
        # morphir-scala submodule bump does not start the Rust jobs.
        self.assertNotIn("build-scala-extension", self.workflow)
        self.assertNotIn("graalvm/setup-graalvm", self.workflow)
        self.assertNotIn("cache-scala-native-image", self.workflow)
        self.assertNotIn("- 'ecosystem/morphir-scala'", self.rust_filter)
        self.assertFalse(
            (REPO_ROOT / ".github" / "actions" / "cache-scala-native-image").exists()
        )

    def test_cli_job_runs_real_scala_provider_integration(self) -> None:
        self.assertIn(
            f"MORPHIR_SCALA_ELM_EXTENSION_BIN: >-\n            {PUBLISHED}/morphir-scala-elm",
            self.cli_job,
        )
        # The CLI refuses a provider whose reported version differs from the installed one.
        self.assertIn("MORPHIR_SCALA_ELM_EXTENSION_VERSION=", self.cli_job)
        self.assertIn(".dev/out/published-bundles/scala-elm/version.txt", self.cli_job)
        self.assertIn(
            "real_installed_morphir_scala_elm_is_selected_and_activates_offline",
            self.cli_job,
        )
        # The executable has to exist before the test uses it.
        self.assertLess(
            self.cli_job.index("mise run ci:fetch-published-bundles"),
            self.cli_job.index(
                "real_installed_morphir_scala_elm_is_selected_and_activates_offline"
            ),
        )


if __name__ == "__main__":
    unittest.main()
