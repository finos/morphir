import styles from "./TopBar.module.css";

export type ConnectionState = "connecting" | "connected" | "reloading";
export type ViewMode = "doc" | "map" | "ir";

export interface TopBarProps {
    readonly rootName: string;
    readonly connection: ConnectionState;
    readonly view: ViewMode;
    readonly onChangeView: (v: ViewMode) => void;
}

const LABEL: Record<ConnectionState, string> = {
    connecting: "connecting",
    connected: "live",
    reloading: "reloading",
};

export function TopBar({
    rootName,
    connection,
    view,
    onChangeView,
}: TopBarProps): JSX.Element {
    const statusClass = `${styles.status} ${styles[connection] ?? ""}`.trim();
    return (
        <header className={styles.topbar}>
            <div className={styles.brand}>
                <img src="/logo.svg" alt="" />
                <div className={styles.wordmark}>
                    <div className={styles.parentProjectName}>Morphir</div>
                    <div className={styles.projectName}>Substrate</div>
                </div>
            </div>
            {rootName && (
                <div className={styles.rootPath} title={rootName}>
                    {rootName}
                </div>
            )}
            <div
                className={styles.viewToggle}
                role="tablist"
                aria-label="View mode"
            >
                <button
                    type="button"
                    role="tab"
                    aria-selected={view === "doc"}
                    className={
                        view === "doc"
                            ? `${styles.viewBtn} ${styles.viewBtnActive}`
                            : styles.viewBtn
                    }
                    onClick={() => onChangeView("doc")}
                >
                    Document
                </button>
                <button
                    type="button"
                    role="tab"
                    aria-selected={view === "map"}
                    className={
                        view === "map"
                            ? `${styles.viewBtn} ${styles.viewBtnActive}`
                            : styles.viewBtn
                    }
                    onClick={() => onChangeView("map")}
                >
                    Map
                </button>
                <button
                    type="button"
                    role="tab"
                    aria-selected={view === "ir"}
                    className={
                        view === "ir"
                            ? `${styles.viewBtn} ${styles.viewBtnActive}`
                            : styles.viewBtn
                    }
                    onClick={() => onChangeView("ir")}
                >
                    IR
                </button>
            </div>
            <div className={statusClass}>
                <span className={styles.dot} />
                <span>{LABEL[connection]}</span>
            </div>
        </header>
    );
}
