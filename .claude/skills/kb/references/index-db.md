# The SQLite Index

`morphir kb index` builds a SQLite database over the knowledge base so that full-text search, link-graph traversal
and frontmatter faceting are single queries rather than a re-parse of every file.

The database is **derived state**. Everything in it is recomputed from the markdown, it lives under `.dev/kb/index.db`
with the rest of the tooling output, and it is gitignored. Deleting it costs a rebuild and nothing else — never treat
it as a source of truth, and never hand-edit it.

```bash
morphir kb index
```

```bash
morphir kb index --status
```

`--status` prints when the index was built and lists any markdown file modified since. Rebuild before trusting a
query if that list is non-empty; there is no automatic invalidation.

## Fast search

```bash
morphir kb search --query "entry point" --index
```

`--index` routes through FTS5 rather than the file scan. It searches **bodies as well as metadata**, ranks by bm25
with title and description weighted above body text, and returns a highlighted snippet. `--limit` caps the rows
(default 20).

The non-indexed `search` is still the right tool for structured filtering — `--type`, `--tag`, `--status` — since
those are exact-match facets rather than relevance ranking.

FTS5 query syntax is available: `"exact phrase"`, `AND`/`OR`/`NOT`, `pre*` prefixes, and `col:term` to scope to a
column.

## Arbitrary queries

```bash
morphir kb query --sql "SELECT type, count(*) FROM v_concept GROUP BY type ORDER BY 2 DESC"
```

Read-only: `SELECT`, `WITH`, `PRAGMA` and `EXPLAIN` are accepted, anything else is refused. Add `--json` for
structured rows.

## Schema

```
bundle       id, label, name, grp, okf_version, title, description, root_path
doc          id, bundle_id, bundle_path, rel_path, file_path, kind,
             type, title, description, status, stale_after, resource,
             has_frontmatter, frontmatter_error, body_lines, body_chars
frontmatter  doc_id, key, value
tag          doc_id, tag
source       doc_id, source_id, resource, title, org, repo, commit_sha, src_path
link         doc_id, dest, text, line, kind, target_doc_id
heading      doc_id, level, text, slug, line
doc_fts      bundle_path, title, description, body        -- FTS5, rowid = doc.id
meta         key, value                                    -- schema_version, kb_root, built_at
```

`doc.kind` is `RootIndex`, `SubIndex`, `Log` or `Concept` — the same distinction OKF draws between reserved filenames
and concept documents.

`frontmatter` holds every key as a string, which is what lets views pivot register fields — intent `state`, `kind`
and the like — without the `doc` table growing a column per register.

`link.kind` is `bundle`, `relative`, `external` or `anchor`. `target_doc_id` is resolved for bundle-relative links
that hit a document in the same bundle, and null otherwise — so a null `target_doc_id` on a `bundle` link is a broken
link.

`source` splits commit-pinned GitHub URLs into `org`, `repo`, `commit_sha` and `src_path`, which is what makes
"everything sourced from this repo" a one-line query.

`heading` skips headings inside fenced code blocks, so a `# comment` in a shell example does not become a section.

### Views

| View | Gives |
| ---- | ----- |
| `v_concept` | Concepts joined to their bundle — the table you usually want |
| `v_backlink` | Inbound links per document: `doc_id`, `from_path`, `from_bundle`, `line` |
| `v_intent` | Intent records with their register facets pivoted out of `frontmatter` |
| `v_orphan` | Concepts nothing links to |

## Worked queries

**What links here** — the question the markdown cannot answer without a full scan:

```bash
morphir kb query --sql "SELECT from_bundle, from_path, line FROM v_backlink JOIN doc d ON d.id = v_backlink.doc_id WHERE d.bundle_path = '/naming.md'"
```

**Concepts nothing links to:**

```bash
morphir kb query --sql "SELECT bundle, bundle_path, title FROM v_orphan"
```

**Everything drawn from one upstream repository, newest pin first:**

```bash
morphir kb query --sql "SELECT DISTINCT s.commit_sha, count(*) AS docs FROM source s WHERE s.repo = 'morphir-elm' GROUP BY s.commit_sha"
```

**Tag co-occurrence — which tags travel together:**

```bash
morphir kb query --sql "SELECT a.tag, b.tag, count(*) AS n FROM tag a JOIN tag b ON a.doc_id = b.doc_id AND a.tag < b.tag GROUP BY 1,2 HAVING n > 3 ORDER BY n DESC LIMIT 15"
```

**Draft concepts past their review date:**

```bash
morphir kb query --sql "SELECT bundle, bundle_path, stale_after FROM v_concept WHERE status = 'draft' AND stale_after < date('now') ORDER BY stale_after"
```

**Where a term appears, by document, with the heading it sits under** — combine FTS with `heading`:

```bash
morphir kb query --sql "SELECT d.bundle_path, h.text FROM doc_fts f JOIN doc d ON d.id = f.rowid JOIN heading h ON h.doc_id = d.id WHERE doc_fts MATCH 'incompleteness' AND h.level = 2"
```

**Cross-bundle link traffic** — which bundles reference which:

```bash
morphir kb query --sql "SELECT sb.label AS from_bundle, tb.label AS to_bundle, count(*) AS n FROM link l JOIN doc s ON s.id = l.doc_id JOIN bundle sb ON sb.id = s.bundle_id JOIN doc t ON t.id = l.target_doc_id JOIN bundle tb ON tb.id = t.bundle_id GROUP BY 1,2"
```

## Relationship to `morphir kb check`

They overlap but are not substitutes. `check` re-reads the markdown and is always current; the index is a snapshot
and can be stale. Use `check` for correctness and CI, the index for exploration and for questions `check` does not
ask — backlinks, orphans, tag distributions, per-repo provenance.
