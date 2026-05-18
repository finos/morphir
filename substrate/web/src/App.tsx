import { useCallback, useEffect, useState } from "react";
import { TopBar, type ConnectionState } from "./components/TopBar/TopBar";
import { Tree } from "./components/Tree/Tree";
import { Viewer } from "./components/Viewer/Viewer";
import { useLiveReload } from "./hooks/useLiveReload";
import { useTree } from "./hooks/useTree";
import { useDoc } from "./hooks/useDoc";
import { readPathFromURL, urlForPath } from "./router";
import type { WsMessage } from "./types";
import styles from "./App.module.css";

const STRUCTURAL_EVENTS = new Set<WsMessage["type"]>([
    "add",
    "unlink",
    "addDir",
    "unlinkDir",
]);

export function App(): JSX.Element {
    const [activePath, setActivePathState] = useState<string | null>(
        readPathFromURL,
    );
    const [reloadFlash, setReloadFlash] = useState(false);

    const { tree, refresh: refreshTree } = useTree();
    const { doc, loading, error, refresh: refreshDoc } = useDoc(activePath);

    // Replace the *first* history entry with a canonical URL so back/forward
    // works from the moment the page loads.
    useEffect(() => {
        window.history.replaceState(
            { path: activePath },
            "",
            urlForPath(activePath),
        );
        // Run once on mount.
        // eslint-disable-next-line react-hooks/exhaustive-deps
    }, []);

    // Push a new history entry whenever the user navigates within the SPA.
    const navigateTo = useCallback((path: string | null, hash?: string) => {
        setActivePathState((prev) => {
            const url = urlForPath(path, hash);
            const sameDoc = prev === path;
            if (sameDoc && hash) {
                // Same document, new fragment — just update the URL hash
                // and let the browser scroll. No new history entry.
                window.history.replaceState({ path }, "", url);
            } else if (!sameDoc) {
                window.history.pushState({ path }, "", url);
            }
            return path;
        });
    }, []);

    // Tree clicks should update history too.
    const handleTreeSelect = useCallback(
        (path: string) => navigateTo(path),
        [navigateTo],
    );

    // Back/forward: sync state from the URL.
    useEffect(() => {
        const onPop = (): void => {
            setActivePathState(readPathFromURL());
        };
        window.addEventListener("popstate", onPop);
        return () => window.removeEventListener("popstate", onPop);
    }, []);

    const handleWatcherEvent = useCallback(
        (msg: WsMessage) => {
            if (STRUCTURAL_EVENTS.has(msg.type)) refreshTree();

            if (activePath && msg.path === activePath) {
                if (msg.type === "unlink") {
                    navigateTo(null);
                    return;
                }
                if (msg.type === "add" || msg.type === "change") {
                    refreshDoc();
                    setReloadFlash(true);
                }
            }
        },
        [activePath, refreshTree, refreshDoc, navigateTo],
    );

    const wsStatus = useLiveReload(handleWatcherEvent);

    useEffect(() => {
        if (!reloadFlash) return;
        const t = window.setTimeout(() => setReloadFlash(false), 400);
        return () => window.clearTimeout(t);
    }, [reloadFlash]);

    // After a doc loads, if the URL has a fragment, scroll to that anchor.
    useEffect(() => {
        if (!doc) return;
        const hash = window.location.hash.slice(1);
        if (!hash) return;
        const el = document.getElementById(hash);
        if (el) el.scrollIntoView({ block: "start" });
    }, [doc]);

    const connection: ConnectionState = reloadFlash ? "reloading" : wsStatus;

    return (
        <div className={styles.app}>
            <TopBar rootName={tree?.name ?? ""} connection={connection} />
            <div className={styles.body}>
                <Tree
                    tree={tree}
                    activePath={activePath}
                    onSelect={handleTreeSelect}
                />
                <Viewer
                    doc={doc}
                    loading={loading}
                    error={error}
                    onNavigate={navigateTo}
                />
            </div>
        </div>
    );
}
