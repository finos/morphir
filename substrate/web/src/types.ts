/**
 * Shared types for the Substrate dev UI. The shapes here mirror the JSON
 * served by `src/commands/dev.ts` on the substrate side; keep them in
 * sync.
 */

export type TreeNodeType = "file" | "dir";

export interface TreeNode {
    readonly name: string;
    /** Path relative to the served root, forward-slash separated. */
    readonly path: string;
    readonly type: TreeNodeType;
    readonly children?: readonly TreeNode[];
}

export interface DocResponse {
    /** Path relative to the served root, forward-slash separated. */
    readonly path: string;
    /** Markdown rendered to HTML, ready to inject. */
    readonly html: string;
    /** Raw markdown source (handy for future features). */
    readonly raw: string;
    /**
     * ISO-8601 timestamp of the file's last on-disk modification.
     * Compared against `last-interpreted-at` in each substrate block to
     * flag the interpretation as outdated when the prose has changed
     * since the last review.
     */
    readonly lastModified: string;
}

export type WsEventType =
    | "add"
    | "change"
    | "unlink"
    | "addDir"
    | "unlinkDir";

export interface WsMessage {
    readonly type: WsEventType;
    /** Path relative to the served root, forward-slash separated. */
    readonly path: string;
}

/**
 * Response shape for `GET /api/ir`.
 *
 * Returns the full `morphir.json` distribution together with the
 * pre-computed source-location index so the client can do bidirectional
 * navigation without re-walking the distribution itself.
 */
/**
 * Response shape for `GET /api/simplified-ir`.
 *
 * Returns a list of per-module JSON files produced by `morphir simplify`,
 * each with its forward-slash relative path inside the `simplified-ir/`
 * directory.  The browser inflates these into a `SubstrateDistribution`
 * via `web/src/ir/simplified.ts`.
 */
export interface SimplifiedIRResponse {
    readonly files: ReadonlyArray<{
        readonly relPath: string;
        readonly json: unknown;
    }>;
}

export interface IRResponse {
    /** The raw versioned distribution object (formatVersion + distribution). */
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    readonly distribution: Record<string, any>;
    /**
     * Forward index: IR node path → `{ file, sectionId, text }`.
     * Serialised as an array of `[nodePath, sourceLocation]` pairs so it
     * survives JSON round-trip (Map is not directly serialisable).
     */
    readonly forwardIndex: ReadonlyArray<readonly [string, { file: string; sectionId: string; text: string }]>;
    /**
     * Reverse index: location key (`"<file>#<sectionId>"`) → array of node paths.
     * Serialised as an array of `[locationKey, nodePath[]]` pairs.
     */
    readonly reverseIndex: ReadonlyArray<readonly [string, readonly string[]]>;
}
