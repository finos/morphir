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
