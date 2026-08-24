/**
 * Copy the AI-assistant instructions bundled with the substrate package
 * into a consumer project.
 *
 * Source files live under `assets/ai-instructions/` at the substrate
 * package root:
 *
 *   assets/ai-instructions/claude/substrate-cli/SKILL.md
 *   assets/ai-instructions/copilot/substrate-cli.instructions.md
 *
 * They are copied to:
 *
 *   <project>/.claude/skills/substrate-cli/SKILL.md
 *   <project>/.github/instructions/substrate-cli.instructions.md
 *
 * Both `substrate init` and `substrate install` call this so any consumer
 * automatically gets the substrate skill wired up for Claude and GitHub
 * Copilot. The destination files are considered managed by substrate:
 * they are overwritten on every install.
 */
import { copyFile, mkdir, readFile, stat } from "node:fs/promises";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

export interface AiArtifact {
    /** Source path inside the substrate package, relative to the package root. */
    readonly source: string;
    /** Destination path inside the consumer project, relative to the project root. */
    readonly destination: string;
    /** Human-readable label used in CLI output. */
    readonly label: string;
}

export interface CopiedArtifact {
    readonly label: string;
    readonly destination: string;
    readonly action: "written" | "unchanged";
}

/**
 * The set of AI artifacts shipped with substrate. Keep this list in sync
 * with `assets/ai-instructions/` — every artifact listed here must exist
 * in the package.
 */
export const AI_ARTIFACTS: readonly AiArtifact[] = [
    {
        source: "assets/ai-instructions/claude/substrate-cli/SKILL.md",
        destination: ".claude/skills/substrate-cli/SKILL.md",
        label: "Claude skill",
    },
    {
        source: "assets/ai-instructions/copilot/substrate-cli.instructions.md",
        destination: ".github/instructions/substrate-cli.instructions.md",
        label: "GitHub Copilot instructions",
    },
    {
        source: "assets/ai-instructions/claude/substrate-interpretation/SKILL.md",
        destination: ".claude/skills/substrate-interpretation/SKILL.md",
        label: "Claude interpretation skill",
    },
    {
        source: "assets/ai-instructions/copilot/substrate-interpretation.instructions.md",
        destination: ".github/instructions/substrate-interpretation.instructions.md",
        label: "GitHub Copilot interpretation instructions",
    },
];

/**
 * Copy every AI artifact into the consumer project rooted at
 * `projectRoot`. Returns a record of what was written so the CLI can
 * report it. Silently no-ops for artifacts whose source file is missing
 * — this keeps the command working in dev trees where the npm package
 * layout is not fully assembled.
 */
export async function installAiInstructions(
    projectRoot: string,
): Promise<readonly CopiedArtifact[]> {
    const pkgRoot = await locatePackageRoot();
    if (pkgRoot === null) return [];

    const results: CopiedArtifact[] = [];
    for (const artifact of AI_ARTIFACTS) {
        const src = join(pkgRoot, artifact.source);
        if (!(await fileExists(src))) continue;
        const dest = join(projectRoot, artifact.destination);
        const action = await copyIfChanged(src, dest);
        results.push({ label: artifact.label, destination: dest, action });
    }
    return results;
}

/**
 * Locate the substrate package root by walking up from this compiled
 * module's directory looking for a `package.json` whose name is
 * `@morphir/substrate`. Returns null if not found (e.g. when the package
 * has been installed in an unusual layout).
 */
async function locatePackageRoot(): Promise<string | null> {
    const here = fileURLToPath(new URL(".", import.meta.url));
    let dir = resolve(here);
    while (true) {
        const candidate = join(dir, "package.json");
        if (await fileExists(candidate)) {
            try {
                const raw = await readFile(candidate, "utf8");
                const parsed = JSON.parse(raw) as { name?: string };
                if (parsed.name === "@morphir/substrate") return dir;
            } catch {
                // Unreadable package.json — keep walking.
            }
        }
        const parent = dirname(dir);
        if (parent === dir) return null;
        dir = parent;
    }
}

async function copyIfChanged(
    src: string,
    dest: string,
): Promise<"written" | "unchanged"> {
    if (await fileExists(dest)) {
        const [a, b] = await Promise.all([
            readFile(src, "utf8"),
            readFile(dest, "utf8"),
        ]);
        if (a === b) return "unchanged";
    }
    await mkdir(dirname(dest), { recursive: true });
    await copyFile(src, dest);
    return "written";
}

async function fileExists(path: string): Promise<boolean> {
    try {
        const s = await stat(path);
        return s.isFile();
    } catch {
        return false;
    }
}
