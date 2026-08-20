import { describe, it, expect, beforeEach, afterEach } from "vitest";
import { mkdtemp, readFile, rm, stat, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";

import {
    AI_ARTIFACTS,
    installAiInstructions,
} from "../../src/commands/ai-instructions.js";

let tmp: string;

beforeEach(async () => {
    tmp = await mkdtemp(join(tmpdir(), "substrate-ai-"));
});

afterEach(async () => {
    await rm(tmp, { recursive: true, force: true });
});

describe("AI_ARTIFACTS", () => {
    it("includes the Claude skill", () => {
        const claude = AI_ARTIFACTS.find((a) =>
            a.destination.startsWith(".claude/"),
        );
        expect(claude).toBeDefined();
        expect(claude!.source).toBe(
            "assets/ai-instructions/claude/substrate-cli/SKILL.md",
        );
        expect(claude!.destination).toBe(
            ".claude/skills/substrate-cli/SKILL.md",
        );
    });

    it("includes the GitHub Copilot instructions", () => {
        const copilot = AI_ARTIFACTS.find((a) =>
            a.destination.startsWith(".github/"),
        );
        expect(copilot).toBeDefined();
        expect(copilot!.source).toBe(
            "assets/ai-instructions/copilot/substrate-cli.instructions.md",
        );
        expect(copilot!.destination).toBe(
            ".github/instructions/substrate-cli.instructions.md",
        );
    });
});

describe("installAiInstructions", () => {
    it("writes both artifacts into a fresh project", async () => {
        const results = await installAiInstructions(tmp);
        expect(results.length).toBeGreaterThan(0);
        for (const a of AI_ARTIFACTS) {
            const s = await stat(join(tmp, a.destination));
            expect(s.isFile()).toBe(true);
        }
        for (const r of results) {
            expect(r.action).toBe("written");
        }
    });

    it("creates parent directories as needed", async () => {
        await installAiInstructions(tmp);
        const claudeDir = await stat(join(tmp, ".claude", "skills", "substrate-cli"));
        const copilotDir = await stat(join(tmp, ".github", "instructions"));
        expect(claudeDir.isDirectory()).toBe(true);
        expect(copilotDir.isDirectory()).toBe(true);
    });

    it("reports unchanged on a second run with no edits", async () => {
        await installAiInstructions(tmp);
        const second = await installAiInstructions(tmp);
        for (const r of second) {
            expect(r.action).toBe("unchanged");
        }
    });

    it("overwrites a user-edited destination back to the bundled content", async () => {
        await installAiInstructions(tmp);
        const claudePath = join(
            tmp,
            ".claude",
            "skills",
            "substrate-cli",
            "SKILL.md",
        );
        const original = await readFile(claudePath, "utf8");
        await writeFile(claudePath, "tampered content\n", "utf8");

        const second = await installAiInstructions(tmp);
        const claude = second.find((r) =>
            r.destination.endsWith("SKILL.md"),
        );
        expect(claude!.action).toBe("written");

        const restored = await readFile(claudePath, "utf8");
        expect(restored).toBe(original);
    });

    it("emits SKILL.md with valid Claude skill frontmatter", async () => {
        await installAiInstructions(tmp);
        const claude = await readFile(
            join(tmp, ".claude", "skills", "substrate-cli", "SKILL.md"),
            "utf8",
        );
        expect(claude.startsWith("---\n")).toBe(true);
        expect(claude).toMatch(/\nname: substrate-cli\n/);
        expect(claude).toMatch(/\ndescription: /);
    });

    it("emits Copilot instructions with applyTo frontmatter", async () => {
        await installAiInstructions(tmp);
        const copilot = await readFile(
            join(tmp, ".github", "instructions", "substrate-cli.instructions.md"),
            "utf8",
        );
        expect(copilot.startsWith("---\n")).toBe(true);
        expect(copilot).toMatch(/\napplyTo: /);
    });

    it("covers refactor rename in the Claude skill", async () => {
        await installAiInstructions(tmp);
        const claude = await readFile(
            join(tmp, ".claude", "skills", "substrate-cli", "SKILL.md"),
            "utf8",
        );
        expect(claude).toMatch(/substrate refactor rename/);
        // The three operation shapes should be explained.
        expect(claude).toMatch(/Rename a file/i);
        expect(claude).toMatch(/Rename a section/i);
        expect(claude).toMatch(/Move a section/i);
    });
});
