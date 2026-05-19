import type { JSX } from "react";
import type { ParseDiagnostic } from "../../substrate/ast";
import styles from "./Diagnostics.module.css";

export interface DiagnosticsProps {
    readonly diagnostics: readonly ParseDiagnostic[];
}

export function Diagnostics({ diagnostics }: DiagnosticsProps): JSX.Element | null {
    if (diagnostics.length === 0) return null;
    return (
        <ul className={styles.list} role="alert">
            {diagnostics.map((d, i) => (
                <li
                    key={i}
                    className={
                        d.severity === "error" ? styles.error : styles.warning
                    }
                >
                    <span className={styles.severity}>{d.severity}</span>
                    <span className={styles.message}>{d.message}</span>
                    {d.position && (
                        <span className={styles.position}>
                            line {d.position.line}, col {d.position.col}
                        </span>
                    )}
                    {d.path && d.path.length > 0 && (
                        <span className={styles.path}>
                            at {d.path.map((p) => String(p)).join(" / ")}
                        </span>
                    )}
                </li>
            ))}
        </ul>
    );
}
