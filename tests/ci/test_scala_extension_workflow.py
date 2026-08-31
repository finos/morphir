import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
CI_WORKFLOW_PATH = REPO_ROOT / ".github" / "workflows" / "ci.yml"


class ScalaExtensionWorkflowTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.workflow = CI_WORKFLOW_PATH.read_text(encoding="utf-8")
        cls.rust_filter = cls.workflow.split(
            "            rust:\n", maxsplit=1
        )[1].split("            docs:\n", maxsplit=1)[0]
        # Parallelized: Scala build is in build-scala-extension, integration is in morphir-cli-test
        cls.scala_build_job = cls.workflow.split(
            "  build-scala-extension:\n", maxsplit=1
        )[1].split("  morphir-cli-test:\n", maxsplit=1)[0]
        cls.cli_job = cls.workflow.split(
            "  morphir-cli-test:\n", maxsplit=1
        )[1].split("  docs:\n", maxsplit=1)[0]

    def test_scala_submodule_pointer_triggers_cli_validation(self) -> None:
        self.assertIn("- 'ecosystem/morphir-scala'", self.rust_filter)

    def test_cli_job_builds_real_scala_provider_with_graalvm(self) -> None:
        # Build step lives in build-scala-extension (parallelized from morphir-cli)
        self.assertIn("uses: graalvm/setup-graalvm@v1", self.scala_build_job)
        self.assertIn(
            "morphir.langkit.elm.compiler.mep.jvm.nativeImage", self.scala_build_job
        )
        self.assertIn(
            "morphir.langkit.elm.compiler.mep.jvm.mepProviderVersion",
            self.scala_build_job,
        )
        self.assertIn("json.load(sys.stdin)", self.scala_build_job)

    def test_cli_job_runs_real_scala_provider_integration(self) -> None:
        self.assertIn("MORPHIR_SCALA_ELM_EXTENSION_BIN:", self.cli_job)
        self.assertIn("MORPHIR_SCALA_ELM_EXTENSION_VERSION", self.cli_job)
        self.assertIn(
            "real_installed_morphir_scala_elm_is_selected_and_activates_offline",
            self.cli_job,
        )


if __name__ == "__main__":
    unittest.main()
