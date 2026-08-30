from __future__ import annotations

import importlib.util
import tempfile
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[4]
SCRIPT_PATH = REPO_ROOT / ".claude/skills/technical-writer/scripts/generate_llms_txt.py"
SPEC = importlib.util.spec_from_file_location("generate_llms_txt", SCRIPT_PATH)
assert SPEC and SPEC.loader
GENERATOR = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(GENERATOR)


class GeneratedDocumentLinkTests(unittest.TestCase):
    def test_percent_encoded_morphir_web_ui_path_is_not_double_encoded(self) -> None:
        source = REPO_ROOT / "docs/README.md"
        content = source.read_text(encoding="utf-8")

        cleaned = GENERATOR.clean_content_for_llm(
            content,
            source_path=source,
            docs_dir=REPO_ROOT / "docs",
        )

        expected = (
            "https://morphir.finos.org/docs/getting-started/"
            "Morphir%20Web%20UI"
        )
        self.assertIn(expected, cleaned)
        self.assertNotIn("Morphir%2520Web%2520UI", cleaned)

    def test_percent_encoded_frontmatter_route_keeps_query_and_fragment(self) -> None:
        source = REPO_ROOT / "docs/README.md"
        content = (
            "[JSON Schema guide](reference/json-schema/"
            "json-schema-enabled%20developers%20guide.md"
            "?view=source#overview)"
        )

        cleaned = GENERATOR.clean_content_for_llm(
            content,
            source_path=source,
            docs_dir=REPO_ROOT / "docs",
        )

        expected = (
            "[JSON Schema guide](https://morphir.finos.org/docs/reference/"
            "json-schema/json-schema-enabled-decorator?view=source#overview)"
        )
        self.assertEqual(expected, cleaned)
        self.assertNotIn("%2520", cleaned)

    def test_percent_encoded_traversal_stays_outside_generated_site_routes(self) -> None:
        source = REPO_ROOT / "docs/README.md"
        content = "[Outside](%2e%2e/secret.md?view=source#details)"

        cleaned = GENERATOR.clean_content_for_llm(
            content,
            source_path=source,
            docs_dir=REPO_ROOT / "docs",
        )

        self.assertEqual(content, cleaned)

    def test_overview_proposal_link_resolves_from_its_source_directory(self) -> None:
        source = REPO_ROOT / "docs/design/draft/extensions/README.mdx"
        content = source.read_text(encoding="utf-8")

        cleaned = GENERATOR.clean_content_for_llm(
            content,
            source_path=source,
            docs_dir=REPO_ROOT / "docs",
        )

        expected = (
            "https://morphir.finos.org/docs/design/proposals/"
            "wasm-extension-runtime-and-avro-backend"
        )
        self.assertIn(expected, cleaned)

    def test_full_snapshot_resolves_overview_links_to_real_doc_routes(self) -> None:
        generated = GENERATOR.generate_full({}, REPO_ROOT / "docs")

        expected_routes = (
            "docs/design/draft/extensions/protocol",
            "docs/design/draft/extensions/distribution-and-acquisition",
            "docs/design/draft/extensions/tasks",
        )
        for route in expected_routes:
            with self.subTest(route=route):
                self.assertIn(f"https://morphir.finos.org/{route}", generated)

    def test_full_snapshot_preserves_the_avro_local_install_fragment(self) -> None:
        generated = GENERATOR.generate_full({}, REPO_ROOT / "docs")

        expected = (
            "https://morphir.finos.org/docs/generate/avro"
            "#build-and-install-the-local-extension"
        )
        self.assertIn(expected, generated)
        self.assertNotRegex(generated, r"\.mdx?#[^\s)]+/")

    def test_readme_and_index_links_use_their_parent_routes(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            docs_dir = Path(temporary_directory)
            source = docs_dir / "section/source.md"
            source.parent.mkdir(parents=True)
            (docs_dir / "guide").mkdir()
            (docs_dir / "guide/README.md").write_text("# Guide\n", encoding="utf-8")
            (docs_dir / "spec").mkdir()
            (docs_dir / "spec/index.mdx").write_text("# Spec\n", encoding="utf-8")

            cleaned = GENERATOR.clean_content_for_llm(
                "[Guide](../guide/README.md) [Spec](../spec/index.mdx)",
                source_path=source,
                docs_dir=docs_dir,
            )

        self.assertIn(
            "[Guide](https://morphir.finos.org/docs/guide/)", cleaned
        )
        self.assertIn(
            "[Spec](https://morphir.finos.org/docs/spec/)", cleaned
        )

    def test_target_slug_overrides_its_file_route(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            docs_dir = Path(temporary_directory)
            source = docs_dir / "section/source.md"
            source.parent.mkdir(parents=True)
            target = docs_dir / "target.md"
            target.write_text(
                "---\nslug: /published-target\n---\n# Target\n",
                encoding="utf-8",
            )

            cleaned = GENERATOR.clean_content_for_llm(
                "[Target](../target.md#details)",
                source_path=source,
                docs_dir=docs_dir,
            )

        self.assertEqual(
            "[Target](https://morphir.finos.org/docs/published-target#details)",
            cleaned,
        )

    def test_target_id_replaces_its_file_name_in_the_route(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            docs_dir = Path(temporary_directory)
            source = docs_dir / "section/source.md"
            source.parent.mkdir(parents=True)
            target = docs_dir / "section/target.md"
            target.write_text(
                "---\nid: published-target\n---\n# Target\n",
                encoding="utf-8",
            )

            cleaned = GENERATOR.clean_content_for_llm(
                "[Target](target.md#details)",
                source_path=source,
                docs_dir=docs_dir,
            )

        self.assertEqual(
            (
                "[Target](https://morphir.finos.org/docs/section/"
                "published-target#details)"
            ),
            cleaned,
        )

    def test_index_route_ignores_its_document_id(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            docs_dir = Path(temporary_directory)
            source = docs_dir / "source.md"
            section = docs_dir / "section"
            section.mkdir()
            target = section / "index.md"
            target.write_text(
                "---\nid: section-index\n---\n# Section\n",
                encoding="utf-8",
            )

            cleaned = GENERATOR.clean_content_for_llm(
                "[Section](section/index.md)",
                source_path=source,
                docs_dir=docs_dir,
            )

        self.assertEqual(
            "[Section](https://morphir.finos.org/docs/section/)",
            cleaned,
        )

    def test_full_snapshot_keeps_every_key_document(self) -> None:
        generated = GENERATOR.generate_full({}, REPO_ROOT / "docs")

        self.assertNotIn("<!-- Failed to load", generated)


if __name__ == "__main__":
    unittest.main()
