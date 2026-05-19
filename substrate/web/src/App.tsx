import { useCallback, useEffect, useRef, useState } from "react";
import {
    TopBar,
    type ConnectionState,
    type ViewMode,
} from "./components/TopBar/TopBar";
import { Tree } from "./components/Tree/Tree";
import { Viewer } from "./components/Viewer/Viewer";
import { MapView } from "./components/MapView/MapView";
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
    const [view, setView] = useState<ViewMode>("doc");
    const [reloadFlash, setReloadFlash] = useState(false);
    const closeTreeDropdownRef = useRef<(() => void) | null>(null);

    const { tree, refresh: refreshTree } = useTree();
    const { doc, loading, error, refresh: refreshDoc } = useDoc(activePath);

    useEffect(() => {
        window.history.replaceState(
            { path: activePath },
            "",
            urlForPath(activePath),
        );
        // eslint-disable-next-line react-hooks/exhaustive-deps
    }, []);

    const navigateTo = useCallback((path: string | null, hash?: string) => {
        setActivePathState((prev) => {
            const url = urlForPath(path, hash);
            const sameDoc = prev === path;
            if (sameDoc && hash) {
                window.history.replaceState({ path }, "", url);
            } else if (!sameDoc) {
                window.history.pushState({ path }, "", url);
            }
            return path;
        });
    }, []);

    const handleTreeSelect = useCallback(
        (path: string) => {
            navigateTo(path);
            closeTreeDropdownRef.current?.();
        },
        [navigateTo],
    );

    const registerCloseTreeDropdown = useCallback((close: () => void) => {
        closeTreeDropdownRef.current = close;
    }, []);

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
            <TopBar
                rootName={tree?.name ?? ""}
                connection={connection}
                view={view}
                onChangeView={setView}
            />
            <div
                className={
                    view === "map" ? styles.bodyFullspan : styles.body
                }
            >
                {view === "doc" ? (
                    <Viewer
                        doc={doc}
                        loading={loading}
                        error={error}
                        onNavigate={navigateTo}
                        treeSlot={
                            <Tree
                                tree={tree}
                                activePath={activePath}
                                onSelect={handleTreeSelect}
                            />
                        }
                        activePath={activePath}
                        onRegisterCloseTreeDropdown={registerCloseTreeDropdown}
                    />
                ) : (
                    <MapView
                        tree={tree}
                        onNavigate={(p) => {
                            navigateTo(p);
                            setView("doc");
                        }}
                    />
                )}
            </div>
        </div>
    );
}
