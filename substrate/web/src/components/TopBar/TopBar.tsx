import styles from "./TopBar.module.css";

export type ConnectionState = "connecting" | "connected" | "reloading";

export interface TopBarProps {
    readonly rootName: string;
    readonly connection: ConnectionState;
}

const LABEL: Record<ConnectionState, string> = {
    connecting: "connecting",
    connected: "live",
    reloading: "reloading",
};

export function TopBar({ rootName, connection }: TopBarProps): JSX.Element {
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
            <div className={statusClass}>
                <span className={styles.dot} />
                <span>{LABEL[connection]}</span>
            </div>
        </header>
    );
}
