# Tasks

## 1. Decisions before building (morphir-ukvn.5.97.1)

- [ ] 1.1 Record the server stop policy (command, idle time, or both) in design.html and add its requirement to the
  document-viewer spec; verify with `openspec validate add-mission-control-document-viewer --strict`
- [ ] 1.2 Record what the standalone form is for, and whether `beads-companion design store` writes it, in
  design.html; verify the open question is removed
- [ ] 1.3 Confirm decision D1 (MoonBit native app) in design.html; verify the open question is removed

## 2. App skeleton and server reuse (morphir-ukvn.5.97.2)

- [ ] 2.1 Create `apps/morphir-mission-control` as a MoonBit native module with argparse subcommands `open`, `stop`
  and `status`, `--json` output in the `morphir/command-result` envelope, and a mise task; verify `--help` and a
  self-test run in `mise run test:ci` or the app's own test task
- [ ] 2.2 Serve the checkout on `127.0.0.1` with a free port, `GET /_health`, refusal of paths outside the checkout
  and the script Content-Security-Policy; verify with tests for the health answer, a `..` path and a symlink that
  leaves the checkout
- [ ] 2.3 Write and read `.dev/mission-control/server.json`, reuse a live matching server, and replace a stale record;
  verify with tests for live, stale and different-checkout records, and that a second `open` starts no process

## 3. Viewing documents (morphir-ukvn.5.97.3)

- [ ] 3.1 Resolve any request path that ends in `docs/templates/assets/<file>` to the shared asset; verify that an
  archived design with an uncorrected prefix loads its CSS in a browser test
- [ ] 3.2 Render Markdown files into the agent document template with heading ids, a table of contents and
  highlighted code, using `render_markdown` from `apps/morphir-site/content`; verify with tests on `proposal.md`,
  `tasks.md`, a `spec.md` and a `design.md`
- [ ] 3.3 Add `/_change/<name>/` for active and archived OpenSpec changes, with an index that links to every file;
  verify with a fixture change in a browser test
- [ ] 3.4 Add `/_bead/<id>` that reads the design through the same tracker path as `beads-companion design export`,
  and refuses an unknown id or a bead with no design; verify with tests on fixture data, not the live tracker
- [ ] 3.5 Make `open TARGET` accept a bead id, a change name or a file path and open the browser; verify each target
  kind in tests that check the URL without starting a browser
- [ ] 3.6 Document the app in its README and in the OpenSpec and HTML-document sections of AGENTS.md; verify the
  documented commands run as written

## 4. Standalone and referenced forms (morphir-ukvn.5.97.4)

- [ ] 4.1 Convert a referenced document to standalone with `data-agent-asset` markers; verify the output has no
  `docs/templates/assets/` reference and renders highlighted code from a directory outside the checkout
- [ ] 4.2 Convert a standalone document to referenced with the correct prefix for the output path; verify the
  `.dev/beads-specs/` prefix and the round trip that keeps `<main>` unchanged
- [ ] 4.3 Refuse a document with any other script or stylesheet, naming it; verify with a remote-script fixture that
  no output is written
