import { useCallback, useEffect, useState } from "react";
import { TopBar, type ConnectionState } from "./components/TopBar/TopBar";
import { Tree } from "./components/Tree/Tree";
import { Viewer } from "./components/Viewer/Viewer";
import { useLiveReload } from "./hooks/useLiveReload";
import { useTree } from "./hooks/useTree";
import { useDoc } from "./hooks/useDoc";
import type { WsMessage } from "./types";
import styles from "./App.module.css";

const STRUCTURAL_EVENTS = new Set<WsMessage["type"]>([
    "add",
    "unlink",
    "addDir",
    "unlinkDir",
]);

export function App(): JSX.Element {
    const [activePath, setActivePath] = useState<string | null>(null);
    const [reloadFlash, setReloadFlash] = useState(false);

    const { tree, refresh: refreshTree } = useTree();
    const { doc, loading, error, refresh: refreshDoc } = useDoc(activePath);

    const handleWatcherEvent = useCallback(
        (msg: WsMessage) => {
            if (STRUCTURAL_EVENTS.has(msg.type)) refreshTree();

            if (activePath && msg.path === activePath) {
                if (msg.type === "unlink") {
                    setActivePath(null);
                    return;
                }
                if (msg.type === "add" || msg.type === "change") {
                    refreshDoc();
                    setReloadFlash(true);
                }
            }
        },
        [activePath, refreshTree, refreshDoc],
    );

    const wsStatus = useLiveReload(handleWatcherEvent);

    useEffect(() => {
        if (!reloadFlash) return;
        const t = window.setTimeout(() => setReloadFlash(false), 400);
        return () => window.clearTimeout(t);
    }, [reloadFlash]);

    const connection: ConnectionState = reloadFlash
        ? "reloading"
        : wsStatus;

    return (
        <div className={styles.app}>
            <TopBar rootName={tree?.name ?? ""} connection={connection} />
            <div className={styles.body}>
                <Tree
                    tree={tree}
                    activePath={activePath}
                    onSelect={setActivePath}
                />
                <Viewer doc={doc} loading={loading} error={error} />
            </div>
        </div>
    );
}
