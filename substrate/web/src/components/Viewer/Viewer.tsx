import type { DocResponse } from "../../types";
import styles from "./Viewer.module.css";

export interface ViewerProps {
    readonly doc: DocResponse | null;
    readonly loading: boolean;
    readonly error: Error | null;
}

export function Viewer({ doc, loading, error }: ViewerProps): JSX.Element {
    if (error && !doc) {
        return (
            <main className={styles.viewer}>
                <div className={styles.inner}>
                    <div className={styles.empty}>
                        <div>
                            <div className={styles.emptyTitle}>
                                Couldn't load that file
                            </div>
                            <div>{error.message}</div>
                        </div>
                    </div>
                </div>
            </main>
        );
    }

    if (!doc && loading) {
        return (
            <main className={styles.viewer}>
                <div className={styles.inner}>
                    <div className={styles.empty}>Loading…</div>
                </div>
            </main>
        );
    }

    if (!doc) {
        return (
            <main className={styles.viewer}>
                <div className={styles.inner}>
                    <div className={styles.empty}>
                        <div>
                            <div className={styles.emptyTitle}>
                                Pick a document
                            </div>
                            <div>
                                Select a markdown file from the tree on the
                                left.
                            </div>
                        </div>
                    </div>
                </div>
            </main>
        );
    }

    return (
        <main className={styles.viewer}>
            <div className={styles.inner}>
                <div className={styles.breadcrumb}>
                    {doc.path.split("/").join(" / ")}
                </div>
                <div
                    className={styles.markdown}
                    // Markdown rendered server-side; HTML comes from the
                    // substrate dev API. Treat the source as trusted —
                    // this server only serves local files.
                    dangerouslySetInnerHTML={{ __html: doc.html }}
                />
            </div>
        </main>
    );
}
