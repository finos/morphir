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
