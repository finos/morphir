# `substrate dev`

Start a local development web UI that browses the markdown documents in a
directory. The UI auto-reloads when files change on disk.

This is the day-to-day "open the project in a browser and watch it" command —
not a published site. It is meant to run on the author's machine and serve
only the local filesystem.

## Synopsis

```bash
substrate dev [--dir <path>] [--port <port>] [--host <host>]
```

## Behaviour

- Starts an HTTP server bound to `--host` (default `127.0.0.1`) on `--port`
  (default: a free port chosen by the OS).
- On startup, prints the directory it is serving and the URL on standard out,
  one item per line, so the URL is easy to ctrl/cmd-click in any terminal:

  ```
  substrate dev
    serving: /path/to/dir
    url:     http://127.0.0.1:5173/
    (press Ctrl+C to stop)
  ```

- Serves a single-page React UI:
  - **Left:** a filesystem tree of every `.md` file under the served directory.
    Directories that contain no markdown (transitively) are hidden. Entries
    whose name starts with `.`, plus `node_modules` and `dist`, are skipped.
  - **Main view:** the selected document, rendered as HTML.
- Watches the served directory recursively. On every filesystem event the
  server pushes a notification over a WebSocket (path `/_ws`); the UI then
  re-fetches the affected document (or rebuilds the tree, for adds/removes)
  with no full page reload.
- Ignores hidden entries, `node_modules`, and `dist` when watching, listing,
  and serving.
- Path traversal outside the served root is rejected.

## Options

| Flag | Default | Meaning |
| --- | --- | --- |
| `-d, --dir <path>` | current working directory | Directory to serve. |
| `-p, --port <port>` | `0` (OS-assigned) | TCP port to listen on. |
| `-h, --host <host>` | `127.0.0.1` | Interface to bind to. |

## HTTP API

The dev server exposes a small JSON API consumed by the bundled UI:

- `GET /api/tree` → `{ name, path, type: "dir", children: TreeNode[] }`
- `GET /api/doc?path=<relative>` → `{ path, raw, html }` where `html` is the
  rendered markdown.
- `GET /_ws` → WebSocket; messages are `{ type, path }` where `type` is one of
  `add`, `change`, `unlink`, `addDir`, `unlinkDir` and `path` is relative to
  the served root.

The API is unauthenticated and intentionally local-only. Binding to a
non-loopback `--host` is the user's call; do not do this on an untrusted
network.

## Implementation

The UI is a Vite + React + TypeScript SPA under `web/`. `vite build`
emits a self-contained bundle into `assets/web/`, which this command
serves as static files. End users running `substrate dev` never need
Node tooling beyond the published npm package.

For contributors, the dev loop is `npm run dev:web` from the repo root:
it runs `substrate dev` on `:5173` (API + WebSocket) and the Vite dev
server on `:5174` with HMR. The Vite server proxies `/api` and `/_ws`
to substrate dev — see `web/vite.config.ts` and `web/README.md`.

## Out of scope (for now)

- No substrate-specific rendering (link resolution, type information,
  test-result overlays). The viewer treats files as plain GitHub-flavoured
  markdown.
- No editing — read-only viewer.
- No search.

These are intentional. The first iteration of this command exists to put a
usable browser-based viewer in front of the user; substrate-aware
functionality is added in later passes.
