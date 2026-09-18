import re
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
WORKFLOWS = REPO_ROOT / ".github" / "workflows"
CI_WORKFLOW_PATH = WORKFLOWS / "ci.yml"
RELEASE_WORKFLOW_PATH = WORKFLOWS / "release.yml"
AGENDA_WORKFLOW_PATH = WORKFLOWS / "create-meeting-agenda.yml"
SETUP_RUST_CI_ACTION = REPO_ROOT / ".github" / "actions" / "setup-rust-ci" / "action.yml"

# Inputs that only the kit run against the Rust binding and the migrate
# validation read. None of them is compiled into, or read by the tests of, the
# morphir crate, so none of them may start the full Rust pipeline.
CONFORMANCE_ONLY_INPUTS = [
    "- 'spec/ir/mck/**'",
    "- 'ecosystem/morphir-typescript'",
    "- 'tools/check-mck-report.ts'",
    "- 'tools/run-mck-rust.ts'",
    "- 'tools/rust-mck-command*'",
    "- 'website/scripts/validate-migrated-ir.js'",
    "- 'website/static/schemas/morphir-ir-v4.json'",
    "- 'website/package.json'",
    "- 'website/package-lock.json'",
]


def job_names(workflow: str) -> list[str]:
    jobs = workflow.split("\njobs:\n", maxsplit=1)[1]
    return re.findall(r"^  ([a-z][a-z0-9-]*):\n", jobs, flags=re.MULTILINE)


def job_body(workflow: str, name: str) -> str:
    names = job_names(workflow)
    body = workflow.split(f"\n  {name}:\n", maxsplit=1)[1]
    following = names[names.index(name) + 1 :]
    if following:
        body = body.split(f"\n  {following[0]}:\n", maxsplit=1)[0]
    return body


def filter_body(workflow: str, name: str) -> str:
    body = workflow.split(f"            {name}:\n", maxsplit=1)[1]
    return re.split(r"\n            [a-z-]+:\n|\n\n", body, maxsplit=1)[0]


class PathAwareCiTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.ci = CI_WORKFLOW_PATH.read_text(encoding="utf-8")
        cls.release = RELEASE_WORKFLOW_PATH.read_text(encoding="utf-8")
        cls.agenda = AGENDA_WORKFLOW_PATH.read_text(encoding="utf-8")
        cls.setup_rust = SETUP_RUST_CI_ACTION.read_text(encoding="utf-8")

    # ----- path filters -----

    def test_conformance_inputs_do_not_start_the_rust_pipeline(self) -> None:
        rust_filter = filter_body(self.ci, "rust")
        conformance_filter = filter_body(self.ci, "rust-conformance")
        for entry in CONFORMANCE_ONLY_INPUTS:
            self.assertNotIn(entry, rust_filter)
            self.assertIn(entry, conformance_filter)

    def test_rust_filter_keeps_inputs_the_crate_tests_read(self) -> None:
        rust_filter = filter_body(self.ci, "rust")
        for entry in [
            "- 'crates/**'",
            "- 'Cargo.lock'",
            "- 'ecosystem/morphir-rust'",
            "- 'ecosystem/morphir-scala'",
            "- 'website/static/ir/examples/**'",
            "- '.github/actions/setup-rust-ci/**'",
        ]:
            self.assertIn(entry, rust_filter)

    def test_conformance_job_runs_for_rust_or_conformance_changes(self) -> None:
        job = job_body(self.ci, "rust-conformance")
        self.assertIn("needs: changes", job)
        self.assertIn("needs.changes.outputs.rust == 'true'", job)
        self.assertIn("needs.changes.outputs.rust-conformance == 'true'", job)
        self.assertIn("mise run mck:run-rust", job)
        self.assertIn("mise run migrate:validate", job)

    def test_cli_test_job_no_longer_runs_conformance_steps(self) -> None:
        job = job_body(self.ci, "morphir-cli-test")
        self.assertNotIn("mise run mck:run-rust", job)
        self.assertNotIn("mise run migrate:validate", job)

    def test_docs_job_does_not_repeat_the_package_suite(self) -> None:
        self.assertNotIn("mise run package:check", job_body(self.ci, "docs"))
        self.assertIn("mise run package:check", job_body(self.ci, "package-mck"))

    def test_shared_actions_trigger_the_workflow_tests(self) -> None:
        self.assertIn("- '.github/actions/**'", filter_body(self.ci, "release"))
        self.assertIn("- 'tests/ci/**'", filter_body(self.ci, "release"))

    # ----- aggregate gate -----

    def test_all_checks_needs_every_other_job(self) -> None:
        names = job_names(self.ci)
        needs_line = re.search(r"^    needs: \[(.*)\]$", job_body(self.ci, "check"), re.MULTILINE)
        self.assertIsNotNone(needs_line)
        needs = [item.strip() for item in needs_line.group(1).split(",")]
        self.assertEqual(sorted(needs), sorted(n for n in names if n != "check"))

    def test_all_checks_runs_when_jobs_are_skipped_and_fails_closed(self) -> None:
        check = job_body(self.ci, "check")
        self.assertIn("name: All Checks", check)
        self.assertIn("if: always()", check)
        # A failed change detection leaves every output empty, which would
        # otherwise read as "nothing was required".
        self.assertIn('"${{ needs.changes.result }}" != "success"', check)
        for job in job_names(self.ci):
            if job not in ("changes", "check"):
                self.assertIn(f"needs.{job}.result", check)

    # ----- concurrency -----

    def test_only_pull_request_runs_are_cancelled(self) -> None:
        self.assertIn(
            "  cancel-in-progress: ${{ github.event_name == 'pull_request' }}",
            self.ci,
        )
        self.assertNotIn("cancel-in-progress: true", self.ci)

    def test_release_and_agenda_runs_queue_instead_of_cancelling(self) -> None:
        for workflow in (self.release, self.agenda):
            self.assertIn("\nconcurrency:\n", workflow)
            self.assertIn("  cancel-in-progress: false", workflow)
            self.assertNotIn("cancel-in-progress: true", workflow)

    # ----- caches -----

    def test_rust_cache_has_one_writer(self) -> None:
        self.assertIn("save-cache:", self.setup_rust)
        self.assertRegex(self.setup_rust, r"save-cache:\n(?:    .*\n)*?    default: \"false\"")
        self.assertIn("inputs.save-cache == 'true' &&", self.setup_rust)
        self.assertEqual(self.ci.count('save-cache: "true"'), 1)
        self.assertIn('save-cache: "true"', job_body(self.ci, "morphir-cli-test"))
        self.assertIn('save-cache: "true"', self.release)

    def test_rust_cache_covers_the_submodule_target_directory(self) -> None:
        self.assertIn("ecosystem/morphir-rust -> target", self.setup_rust)

    def test_sccache_only_writes_from_the_default_branch(self) -> None:
        self.assertIn("SCCACHE_GHA_RW_MODE=READ_ONLY", self.setup_rust)
        self.assertIn("github.ref != 'refs/heads/main'", self.setup_rust)

    def test_mise_tool_cache_is_saved_from_main_only(self) -> None:
        uses = self.ci.count("uses: jdx/mise-action@v4")
        self.assertGreater(uses, 0)
        self.assertEqual(
            self.ci.count("cache_save: ${{ github.ref == 'refs/heads/main' }}"),
            uses,
        )

    def test_package_mck_cache_is_saved_from_main_only(self) -> None:
        job = job_body(self.ci, "package-mck")
        self.assertIn("save-if: ${{ github.ref == 'refs/heads/main' }}", job)

    def test_elm_extension_comes_from_its_published_release(self) -> None:
        # finos/morphir-elm owns the build. CI downloads the pinned release archive, so it has
        # no Elm build job and a morphir-elm submodule bump does not start the Rust jobs.
        self.assertNotIn("build-elm-extension", self.ci)
        self.assertNotIn("build:mep-extension", self.ci)
        self.assertNotIn("- 'ecosystem/morphir-elm'", filter_body(self.ci, "rust"))
        job = job_body(self.ci, "morphir-cli-test")
        self.assertIn(
            "${{ github.workspace }}/.dev/out/published-bundles/elm/morphir-elm-extension", job
        )
        # The executable has to exist before the Elm integration tests use it.
        self.assertLess(
            job.index("mise run ci:fetch-published-bundles"),
            job.index("--test elm_extension"),
        )

    # ----- critical path -----

    def test_ci_release_build_skips_fat_lto(self) -> None:
        job = job_body(self.ci, "morphir-cli-test")
        self.assertIn('CARGO_PROFILE_RELEASE_LTO: "off"', job)
        self.assertIn("CARGO_PROFILE_RELEASE_CODEGEN_UNITS:", job)
        # The shipped binary keeps the workspace release profile.
        self.assertNotIn("CARGO_PROFILE_RELEASE", self.release)


if __name__ == "__main__":
    unittest.main()
