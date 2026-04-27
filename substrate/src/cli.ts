#!/usr/bin/env node
/**
 * CLI entry point — the only module with side-effects.
 *
 * Commands:
 *   - `substrate verify <file>` — run the full verification pipeline on a file.
 *   - `substrate init`          — scaffold a new package in the current directory.
 *   - `substrate validate`      — walk the current corpus and check links.
 *   - `substrate install`       — vendor every declared dependency.
 *   - `substrate update [pkg]`  — re-resolve dependencies to latest tags.
 *   - `substrate publish`       — tag and push a library release.
 */
import { Command } from "commander";
import { resolve } from "node:path";
import { verify } from "./pipeline.js";
import { consoleListener, printSummary, exitCode } from "./progress.js";
import { init } from "./commands/init.js";
import { install } from "./commands/install.js";
import { publish } from "./commands/publish.js";
import { update } from "./commands/update.js";
import { reportValidate, validate } from "./commands/validate.js";
import { context } from "./commands/context.js";
import { statsFile, statsStdin, formatStats } from "./commands/stats.js";
import { rename as refactorRename } from "./commands/refactor.js";

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
    .command("init")
    .description(
        "Scaffold a new package in the current directory. Prompts for package " +
            "name, kind, and version (libraries only), then writes substrate.json " +
            "and creates the substrate/ vendor directory.",
    )
    .option("-y, --yes", "Accept all defaults without prompting", false)
    .action(async (opts: { yes: boolean }) => {
        try {
            const result = await init(process.cwd(), { yes: opts.yes });
            console.log(`✓ Created substrate.json for ${result.manifest.name}`);
            console.log("✓ Created substrate/");
        } catch (err: unknown) {
            console.error(err instanceof Error ? err.message : String(err));
            process.exitCode = 1;
        }
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
        "Resolve and vendor every declared dependency into substrate/.",
    )
    .action(async () => {
        try {
            const result = await install(process.cwd());
            for (const entry of result.installed) {
                const mark = entry.action === "already-present" ? "·" : "✓";
                console.log(`  ${mark} ${entry.installName}@${entry.resolved} (${entry.action})`);
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

program
    .command("context <files...>")
    .description(
        "Produce a self-contained, tree-shaken markdown context from one or more " +
            "<file.md[#section]> roots. Follows links transitively and rewrites " +
            "cross-file references as in-document anchors. Output is written to stdout.",
    )
    .option(
        "--no-tree-shaking",
        "Include every referenced file in full instead of tree-shaking to sections.",
    )
    .option(
        "--no-inline",
        "Skip link traversal entirely — only include the explicitly-specified files or sections.",
    )
    .option(
        "--horizontal <path>",
        "Include the named horizontal package: documents in the package are scanned " +
            "for links targeting included corpus sections, and matching horizontal " +
            "sections are pulled in via reverse traversal. Repeatable.",
        (value: string, prior: string[] = []) => [...prior, value],
        [] as string[],
    )
    .action(
        async (
            files: string[],
            opts: { treeShaking: boolean; inline: boolean; horizontal: string[] },
        ) => {
            const result = await context(process.cwd(), files, {
                noTreeShaking: !opts.treeShaking,
                noInline: !opts.inline,
                horizontals: opts.horizontal,
            });
            if (result.errors.length > 0) {
                for (const e of result.errors) console.error(e);
                process.exitCode = 1;
                return;
            }
            process.stdout.write(result.markdown);
        },
    );

program
    .command("stats [file]")
    .description(
        "Print statistics about a markdown file: word count, line count, token estimate, " +
            "link breakdown (external / local / anchors), section count, and heading depth. " +
            "Reads from stdin when no file argument is supplied.",
    )
    .action(async (file: string | undefined) => {
        try {
            const result = file
                ? await statsFile(resolve(process.cwd(), file))
                : await statsStdin();
            console.log(formatStats(result));
        } catch (err: unknown) {
            console.error(err instanceof Error ? err.message : String(err));
            process.exitCode = 1;
        }
    });

const refactor = program
    .command("refactor")
    .description("Refactoring operations on specification files and sections.");

refactor
    .command("rename <from> <to>")
    .description(
        "Rename a file or section, or move a section between files, updating every " +
            "reference in the project.\n\n" +
            "  file.md → other.md          rename file\n" +
            "  file.md#old → file.md#new   rename section heading\n" +
            "  file.md#sec → other.md      move section (prompts for insertion point)\n" +
            "  file.md#sec → other.md#par  move section, append after #par",
    )
    .action(async (from: string, to: string) => {
        try {
            await refactorRename(process.cwd(), from, to);
        } catch (err: unknown) {
            console.error(err instanceof Error ? err.message : String(err));
            process.exitCode = 1;
        }
    });

program.parse(process.argv);
