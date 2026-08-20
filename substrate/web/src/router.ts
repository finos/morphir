/**
 * Tiny URL-routing helpers for the dev UI. We keep the active document
 * path in the `path` query parameter so the dev server can keep serving
 * `index.html` at `/` without any backend awareness of routing.
 */

/** Read the active document path from the current window URL. */
export function readPathFromURL(): string | null {
    const params = new URLSearchParams(window.location.search);
    const p = params.get("path");
    return p && p.length > 0 ? p : null;
}

/** Build the URL we push to history for a given document path. */
export function urlForPath(path: string | null, hash?: string): string {
    const search = path ? `?path=${encodeURIComponent(path)}` : "";
    const frag = hash ? `#${hash}` : "";
    // Always anchor to the current pathname; we never change it.
    return `${window.location.pathname}${search}${frag}`;
}

/**
 * Treat an href as external when it has a URL scheme (http:, https:,
 * mailto:, …) or is protocol-relative. Everything else — absolute paths,
 * relative paths, bare filenames, fragment-only links — is local.
 */
export function isExternalHref(href: string): boolean {
    if (href.startsWith("//")) return true;
    return /^[a-z][a-z0-9+.\-]*:/i.test(href);
}

/**
 * Resolve a local link target against the current document's path.
 *
 * - Absolute (`/foo/bar.md`) is rooted at the served package root.
 * - Relative (`bar.md`, `../sibling/baz.md`) is resolved against the
 *   directory of `currentDocPath`.
 * Returns the normalised path (no leading slash, `..`/`.` collapsed) and
 * any trailing fragment.
 */
export function resolveLocalHref(
    href: string,
    currentDocPath: string | null,
): { readonly path: string; readonly hash: string | null } {
    const hashIdx = href.indexOf("#");
    const hash = hashIdx >= 0 ? href.slice(hashIdx + 1) : null;
    const rawPath = hashIdx >= 0 ? href.slice(0, hashIdx) : href;

    // Pure-fragment link: stay on the current document.
    if (rawPath === "") {
        return { path: currentDocPath ?? "", hash };
    }

    let combined: string;
    if (rawPath.startsWith("/")) {
        combined = rawPath.slice(1);
    } else {
        const dir =
            currentDocPath && currentDocPath.includes("/")
                ? currentDocPath.slice(0, currentDocPath.lastIndexOf("/"))
                : "";
        combined = dir ? `${dir}/${rawPath}` : rawPath;
    }

    const parts: string[] = [];
    for (const seg of combined.split("/")) {
        if (seg === "" || seg === ".") continue;
        if (seg === "..") {
            if (parts.length > 0) parts.pop();
            continue;
        }
        parts.push(seg);
    }

    return { path: parts.join("/"), hash };
}
