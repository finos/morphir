// Substrate dev — React UI.
// No build step: React + htm loaded from esm.sh, served as plain ESM.

import React, {
  useCallback,
  useEffect,
  useMemo,
  useRef,
  useState,
} from "https://esm.sh/react@18.3.1";
import { createRoot } from "https://esm.sh/react-dom@18.3.1/client";
import htm from "https://esm.sh/htm@3.1.1";

const html = htm.bind(React.createElement);

// ─── data ──────────────────────────────────────────────────────
async function fetchTree() {
  const r = await fetch("/api/tree");
  if (!r.ok) throw new Error("tree fetch failed");
  return r.json();
}

async function fetchDoc(path) {
  const r = await fetch(`/api/doc?path=${encodeURIComponent(path)}`);
  if (!r.ok) throw new Error("doc fetch failed");
  return r.json();
}

// ─── tree ──────────────────────────────────────────────────────
function TreeNode({ node, depth, activePath, onSelect, expanded, onToggle }) {
  if (node.type === "file") {
    return html`
      <li>
        <div
          class=${"row" + (activePath === node.path ? " active" : "")}
          onClick=${() => onSelect(node.path)}
          title=${node.path}
        >
          <span class="caret"></span>
          <span class="icon">·</span>
          <span>${node.name.replace(/\.md$/i, "")}</span>
        </div>
      </li>
    `;
  }
  const isOpen = expanded.has(node.path);
  return html`
    <li>
      <div
        class="row"
        onClick=${() => onToggle(node.path)}
        title=${node.path || "/"}
      >
        <span class="caret">${isOpen ? "▾" : "▸"}</span>
        <span class="icon">▦</span>
        <span>${node.name}</span>
      </div>
      ${isOpen &&
      node.children &&
      html`
        <ul class="children">
          ${node.children.map(
            (child) => html`
              <${TreeNode}
                key=${child.path}
                node=${child}
                depth=${depth + 1}
                activePath=${activePath}
                onSelect=${onSelect}
                expanded=${expanded}
                onToggle=${onToggle}
              />
            `,
          )}
        </ul>
      `}
    </li>
  `;
}

function Tree({ tree, activePath, onSelect }) {
  // Default: all directories expanded.
  const [expanded, setExpanded] = useState(() => {
    const set = new Set();
    function walk(n) {
      if (n.type === "dir") {
        set.add(n.path);
        (n.children || []).forEach(walk);
      }
    }
    if (tree) walk(tree);
    return set;
  });

  // Whenever tree shape grows, auto-expand new directories too.
  useEffect(() => {
    if (!tree) return;
    setExpanded((prev) => {
      const next = new Set(prev);
      function walk(n) {
        if (n.type === "dir") {
          if (!next.has(n.path)) next.add(n.path);
          (n.children || []).forEach(walk);
        }
      }
      walk(tree);
      return next;
    });
  }, [tree]);

  const onToggle = useCallback((path) => {
    setExpanded((prev) => {
      const next = new Set(prev);
      if (next.has(path)) next.delete(path);
      else next.add(path);
      return next;
    });
  }, []);

  if (!tree) return html`<div class="tree-eyebrow">Loading…</div>`;

  return html`
    <div class="tree">
      <div class="tree-eyebrow">Files</div>
      <ul>
        ${(tree.children || []).map(
          (child) => html`
            <${TreeNode}
              key=${child.path}
              node=${child}
              depth=${0}
              activePath=${activePath}
              onSelect=${onSelect}
              expanded=${expanded}
              onToggle=${onToggle}
            />
          `,
        )}
      </ul>
      ${(!tree.children || tree.children.length === 0) &&
      html`<div class="tree-eyebrow">No markdown files</div>`}
    </div>
  `;
}

// ─── viewer ────────────────────────────────────────────────────
function Viewer({ doc, loading }) {
  if (!doc && !loading) {
    return html`
      <div class="viewer">
        <div class="viewer-inner">
          <div class="empty">
            <div>
              <div class="big">Pick a document</div>
              <div>Select a markdown file from the tree on the left.</div>
            </div>
          </div>
        </div>
      </div>
    `;
  }
  if (loading && !doc) {
    return html`
      <div class="viewer">
        <div class="viewer-inner">
          <div class="empty">Loading…</div>
        </div>
      </div>
    `;
  }
  const parts = doc.path.split("/");
  return html`
    <div class="viewer">
      <div class="viewer-inner">
        <div class="breadcrumb">${parts.join(" / ")}</div>
        <div
          class="markdown"
          dangerouslySetInnerHTML=${{ __html: doc.html }}
        ></div>
      </div>
    </div>
  `;
}

// ─── live reload ───────────────────────────────────────────────
function useLiveReload(onChange) {
  const [status, setStatus] = useState("connecting");
  const ref = useRef(null);

  useEffect(() => {
    let cancelled = false;
    let backoff = 500;

    function connect() {
      if (cancelled) return;
      const proto = location.protocol === "https:" ? "wss" : "ws";
      const ws = new WebSocket(`${proto}://${location.host}/_ws`);
      ref.current = ws;
      ws.onopen = () => {
        setStatus("connected");
        backoff = 500;
      };
      ws.onclose = () => {
        setStatus("connecting");
        setTimeout(connect, backoff);
        backoff = Math.min(backoff * 2, 5000);
      };
      ws.onerror = () => ws.close();
      ws.onmessage = (ev) => {
        try {
          const msg = JSON.parse(ev.data);
          onChange(msg);
        } catch {
          // ignore
        }
      };
    }
    connect();
    return () => {
      cancelled = true;
      if (ref.current) ref.current.close();
    };
  }, [onChange]);

  return status;
}

// ─── app ───────────────────────────────────────────────────────
function App() {
  const [tree, setTree] = useState(null);
  const [activePath, setActivePath] = useState(null);
  const [doc, setDoc] = useState(null);
  const [loading, setLoading] = useState(false);
  const [flash, setFlash] = useState(false);

  const reloadTree = useCallback(async () => {
    try {
      setTree(await fetchTree());
    } catch (err) {
      console.error(err);
    }
  }, []);

  const loadDoc = useCallback(async (path) => {
    setLoading(true);
    try {
      const d = await fetchDoc(path);
      setDoc(d);
    } catch (err) {
      console.error(err);
      setDoc({ path, html: `<p>Failed to load <code>${path}</code>.</p>` });
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    reloadTree();
  }, [reloadTree]);

  useEffect(() => {
    if (activePath) loadDoc(activePath);
    else setDoc(null);
  }, [activePath, loadDoc]);

  const onChange = useCallback(
    (msg) => {
      // Any structural change → refresh tree.
      if (msg.type === "add" || msg.type === "unlink" ||
          msg.type === "addDir" || msg.type === "unlinkDir") {
        reloadTree();
      }
      // If the currently-viewed file changed → re-fetch it.
      if (activePath && msg.path === activePath &&
          (msg.type === "change" || msg.type === "add")) {
        loadDoc(activePath);
        setFlash(true);
        setTimeout(() => setFlash(false), 400);
      }
      // If the currently-viewed file got deleted → clear it.
      if (activePath && msg.path === activePath && msg.type === "unlink") {
        setActivePath(null);
      }
    },
    [activePath, reloadTree, loadDoc],
  );

  const wsStatus = useLiveReload(onChange);
  const statusLabel = flash
    ? "reloading"
    : wsStatus === "connected"
      ? "live"
      : "connecting";
  const statusClass = flash
    ? "status reloading"
    : wsStatus === "connected"
      ? "status connected"
      : "status";

  const rootName = tree ? tree.name : "";

  return html`
    <div class="app">
      <header class="topbar">
        <div class="brand">
          <img src="/logo.svg" alt="" />
          <span>Substrate</span>
        </div>
        <div class="root-path" title=${rootName}>${rootName}</div>
        <div class=${statusClass}>
          <span class="dot"></span>
          <span>${statusLabel}</span>
        </div>
      </header>
      <div class="body">
        <${Tree}
          tree=${tree}
          activePath=${activePath}
          onSelect=${setActivePath}
        />
        <${Viewer} doc=${doc} loading=${loading} />
      </div>
    </div>
  `;
}

const root = createRoot(document.getElementById("root"));
root.render(html`<${App} />`);
