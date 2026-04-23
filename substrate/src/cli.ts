#!/usr/bin/env node
/**
 * CLI entry point — the only module with side-effects.
 *
 * Commands:
 *   - `substrate verify <file>` — run the full verification pipeline on a file.
 *   - `substrate validate`      — walk the current corpus and check links.
 *   - `substrate install`       — vendor every declared dependency.
 *   - `substrate update [pkg]`  — re-resolve dependencies to latest tags.
 *   - `substrate publish`       — tag and push a library release.
 */
import { Command } from "commander";
import { resolve } from "node:path";
import { verify } from "./pipeline.js";
import { consoleListener, printSummary, exitCode } from "./progress.js";
import { install } from "./commands/install.js";
import { publish } from "./commands/publish.js";
import { update } from "./commands/update.js";
import { reportValidate, validate } from "./commands/validate.js";

const program = new Command();

program
    .name("substrate")
    .description("Verification and package tooling for Morphir Substrate specifications")
    .version("0.1.0");

program
    .command("verify <file>")
    .description(
        "Verify a substrate markdown document through the full pipeline: " +
            "parse → include → lint → references → typecheck → test",
    )
    .option("-q, --quiet", "Suppress progress output; only print the summary", false)
    .action(async (file: string, opts: { quiet: boolean }) => {
        const filePath = resolve(process.cwd(), file);
        const listener = opts.quiet ? undefined : consoleListener();

        console.log(`Verifying: ${filePath}`);

        const result = await verify(filePath, listener);

        printSummary(result);
        process.exitCode = exitCode(result);
    });

program
    .command("validate")
    .description(
        "Walk every markdown file in the current corpus and verify that every " +
            "internal link resolves on disk.",
    )
    .action(async () => {
        try {
            const result = await validate(process.cwd());
            process.exitCode = reportValidate(result);
        } catch (err: unknown) {
            console.error(err instanceof Error ? err.message : String(err));
            process.exitCode = 1;
        }
    });

program
    .command("install")
    .description(
        "Resolve and vendor every declared dependency into substrate/packages/.",
    )
    .action(async () => {
        try {
            const result = await install(process.cwd());
            for (const entry of result.installed) {
                const mark = entry.action === "already-present" ? "·" : "✓";
                console.log(`  ${mark} ${entry.name}@${entry.resolved} (${entry.action})`);
            }
            if (result.wroteLockfile) {
                console.log("✓ Wrote substrate.lock");
            }
            console.log(`✓ Installed ${result.installed.length} package(s)`);
        } catch (err: unknown) {
            console.error(err instanceof Error ? err.message : String(err));
            process.exitCode = 1;
        }
    });

program
    .command("update [package]")
    .description(
        "Re-resolve one (or every) dependency against the latest git tags and " +
            "refresh the lockfile and vendored tree.",
    )
    .action(async (pkg: string | undefined) => {
        try {
            const result = await update(process.cwd(), pkg);
            for (const u of result.updated) {
                const mark = u.changed ? "✓" : "·";
                const from = u.from === null ? "(new)" : u.from;
                console.log(`  ${mark} ${u.name}: ${from} → ${u.to}`);
            }
            console.log("✓ Wrote substrate.lock");
        } catch (err: unknown) {
            console.error(err instanceof Error ? err.message : String(err));
            process.exitCode = 1;
        }
    });

program
    .command("publish")
    .description(
        "Validate the current library package, tag its version, and push the tag.",
    )
    .action(async () => {
        try {
            const result = await publish(process.cwd());
            console.log(`✓ Tagged and pushed ${result.tag}`);
        } catch (err: unknown) {
            console.error(err instanceof Error ? err.message : String(err));
            process.exitCode = 1;
        }
    });

program.parse(process.argv);
