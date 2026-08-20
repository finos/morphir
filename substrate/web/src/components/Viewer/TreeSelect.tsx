import { useEffect, useRef, useState, type ReactNode } from "react";
import styles from "./TreeSelect.module.css";

export interface TreeSelectProps {
    /** Path of the currently active document, shown in the button. */
    readonly activePath: string | null;
    /** Rendered tree placed inside the popover. */
    readonly children: ReactNode;
    /**
     * Called by the host whenever a tree selection has happened, so the
     * popover can close itself. The host wires this by calling
     * `onSelected()` from inside its tree-select handler.
     */
    readonly registerCloseOnSelect?: ((close: () => void) => void) | undefined;
}

export function TreeSelect({
    activePath,
    children,
    registerCloseOnSelect,
}: TreeSelectProps): JSX.Element {
    const [open, setOpen] = useState(false);
    const wrapRef = useRef<HTMLDivElement | null>(null);

    useEffect(() => {
        registerCloseOnSelect?.(() => setOpen(false));
    }, [registerCloseOnSelect]);

    useEffect(() => {
        if (!open) return;
        const onDown = (e: MouseEvent): void => {
            const t = e.target as Node | null;
            if (!t || !wrapRef.current) return;
            if (!wrapRef.current.contains(t)) setOpen(false);
        };
        const onKey = (e: KeyboardEvent): void => {
            if (e.key === "Escape") setOpen(false);
        };
        document.addEventListener("mousedown", onDown);
        document.addEventListener("keydown", onKey);
        return () => {
            document.removeEventListener("mousedown", onDown);
            document.removeEventListener("keydown", onKey);
        };
    }, [open]);

    const labelText = activePath ?? "Choose a file…";

    return (
        <div ref={wrapRef} className={styles["wrap"]}>
            <button
                type="button"
                className={styles["button"]}
                aria-haspopup="listbox"
                aria-expanded={open}
                onClick={() => setOpen((o) => !o)}
                title={activePath ?? "Choose a file"}
            >
                <span
                    className={
                        activePath
                            ? styles["label"]
                            : `${styles["label"]} ${styles["placeholder"]}`
                    }
                >
                    {labelText}
                </span>
                <span className={styles["caret"]} aria-hidden="true">
                    {open ? "▲" : "▼"}
                </span>
            </button>
            {open && (
                <div className={styles["popover"]} role="dialog">
                    <div className={styles["popoverBody"]}>{children}</div>
                </div>
            )}
        </div>
    );
}
