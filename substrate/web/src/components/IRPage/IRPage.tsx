/**
 * Standalone "IR" view, reachable from the TopBar.  Loads the simplified
 * IR distribution from the dev server (output of `morphir simplify`) and
 * hands it to the `IRView` pan/zoom visualisation.
 */
import { useEffect, useState, type JSX } from "react";
import { fetchSimplifiedIR } from "../../api/client";
import {
    buildDistribution,
    inferPackageName,
    type SimplifiedModuleFile,
} from "../../../../src/ir/simplified";
import type { SubstrateDistribution } from "../../ir";
import { IRView } from "../Viewer/Interpretation";
import styles from "./IRPage.module.css";

type State =
    | { kind: "loading" }
    | { kind: "ready"; distribution: SubstrateDistribution }
    | { kind: "missing" }
    | { kind: "error"; message: string };

export function IRPage(): JSX.Element {
    const [state, setState] = useState<State>({ kind: "loading" });

    useEffect(() => {
        let alive = true;
        (async () => {
            try {
                const resp = await fetchSimplifiedIR({ bust: true });
                if (!alive) return;
                if (resp.files.length === 0) {
                    setState({ kind: "missing" });
                    return;
                }
                const files: SimplifiedModuleFile[] = resp.files.map((f) => ({
                    relPath: f.relPath,
                    json: f.json,
                }));
                const pkg = inferPackageName(files) ?? [];
                const distribution = buildDistribution(pkg, files);
                setState({ kind: "ready", distribution });
            } catch (e) {
                if (!alive) return;
                const message = e instanceof Error ? e.message : String(e);
                if (/404/.test(message)) {
                    setState({ kind: "missing" });
                } else {
                    setState({ kind: "error", message });
                }
            }
        })();
        return () => {
            alive = false;
        };
    }, []);

    if (state.kind === "loading") {
        return <div className={styles.message}>Loading simplified IR…</div>;
    }
    if (state.kind === "missing") {
        return (
            <div className={styles.message}>
                <div className={styles.title}>No simplified IR found</div>
                <div className={styles.body}>
                    Run <code>morphir simplify</code> in your project so a{" "}
                    <code>simplified-ir/</code> directory appears next to{" "}
                    <code>morphir.json</code>, then reload.
                </div>
            </div>
        );
    }
    if (state.kind === "error") {
        return (
            <div className={styles.message}>
                <div className={styles.title}>Could not load simplified IR</div>
                <div className={styles.body}>{state.message}</div>
            </div>
        );
    }
    return (
        <div className={styles.host}>
            <IRView distribution={state.distribution} />
        </div>
    );
}
