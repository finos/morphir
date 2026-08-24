/**
 * Generic decision-table visualisation, modelled on the Elm
 * `Morphir.Visual.Components.DecisionTable` component. Each row pairs
 * a list of input patterns with a result value; the optional
 * `highlight` field on a row marks the matched rule.
 */
import type { JSX, ReactNode } from "react";
import styles from "./DecisionTable.module.css";

export interface DecisionTableRow {
    readonly patterns: readonly ReactNode[];
    readonly result: ReactNode;
    /** undefined = neutral, true = matched, false = ruled out. */
    readonly highlight?: boolean;
    /** Stable id linking this row back to a prose phrase. */
    readonly srcId?: string;
}

export interface DecisionTableProps {
    readonly headers: readonly ReactNode[];
    readonly rows: readonly DecisionTableRow[];
}

export function DecisionTable({
    headers,
    rows,
}: DecisionTableProps): JSX.Element {
    return (
        <div className={styles.tableWrap}>
            <table className={styles.table}>
                <thead>
                    <tr>
                        {headers.map((h, i) => (
                            <th key={`h-${i}`} className={styles.header}>
                                {h}
                            </th>
                        ))}
                        <th className={styles.headerArrow} aria-hidden="true" />
                        <th className={styles.header}>Result</th>
                    </tr>
                </thead>
                <tbody>
                    {rows.map((row, ri) => {
                        const cls =
                            row.highlight === true
                                ? styles.matched
                                : row.highlight === false
                                  ? styles.unmatched
                                  : "";
                        return (
                            <tr
                                key={`r-${ri}`}
                                className={cls}
                                {...(row.srcId
                                    ? { "data-src-id": row.srcId }
                                    : {})}
                            >
                                {row.patterns.map((p, pi) => (
                                    <td key={`r-${ri}-p-${pi}`} className={styles.cell}>
                                        {p}
                                    </td>
                                ))}
                                <td className={styles.arrow} aria-hidden="true">
                                    →
                                </td>
                                <td className={styles.cell}>{row.result}</td>
                            </tr>
                        );
                    })}
                </tbody>
            </table>
        </div>
    );
}
