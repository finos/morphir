/**
 * `substrate migrate from morphir` — convert a Morphir IR JSON file to
 * substrate markdown modules, one file per Morphir module.
 */
import { readFile, writeFile, mkdir } from "node:fs/promises";
import { existsSync } from "node:fs";
import { join, dirname } from "node:path";
import { decodeDistribution } from "morphir-elm/ir/distribution";
import type { Name } from "morphir-elm/ir/name";
import type { Path } from "morphir-elm/ir/path";
import type { AccessControlled } from "morphir-elm/ir/access-controlled";
import type { Documented } from "morphir-elm/ir/documented";
import type { Definition as ModuleDefinition } from "morphir-elm/ir/module";
import type {
    Definition as TypeDefinition,
    Type,
} from "morphir-elm/ir/type";
import type { Definition as ValueDefinition } from "morphir-elm/ir/value";

// The Morphir IR produced by `morphir-elm make` uses Type<[]> as the value
// attribute (Va) annotation throughout the package definition.
type Va = Type<[]>;
import type { FQName } from "morphir-elm/ir/fq-name";

// ── Public types ──────────────────────────────────────────────────────────────

export interface MigrateFromMorphirOptions {
    readonly output: string;
    readonly overwrite: boolean;
    readonly dryRun: boolean;
}

export interface MigratedFile {
    readonly path: string;
    readonly content: string;
    readonly action: "written" | "skipped" | "dry-run";
}

export interface MigrateFromMorphirResult {
    readonly files: MigratedFile[];
}

// ── Name / Path helpers ───────────────────────────────────────────────────────

/** Convert a Morphir Name (list of words) to kebab-case: ["my","value"] → "my-value". */
export function nameToKebab(name: Name): string {
    return name.join("-");
}

/** Convert a Morphir Path to a slash-separated file path segment. */
export function pathToFileSegment(path: Path): string {
    return path.map(nameToKebab).join("/");
}

function nameToPascal(name: Name): string {
    return name.map((w) => w.charAt(0).toUpperCase() + w.slice(1)).join("");
}

function nameToCamel(name: Name): string {
    return name
        .map((w, i) => (i === 0 ? w : w.charAt(0).toUpperCase() + w.slice(1)))
        .join("");
}

function fqNameToElm([, , localName]: FQName): string {
    return nameToPascal(localName);
}

// ── Type rendering ────────────────────────────────────────────────────────────

function needsParens(t: Type<[]>): boolean {
    if (t.kind === "Function") return true;
    if (t.kind === "Reference" && t.typeParameters.length > 0) return true;
    return false;
}

function typeToElm(t: Type<[]>): string {
    switch (t.kind) {
        case "Unit":
            return "()";
        case "Variable":
            return nameToCamel(t.name);
        case "Reference": {
            const base = fqNameToElm(t.typeName);
            if (t.typeParameters.length === 0) return base;
            const args = t.typeParameters
                .map((p) => (needsParens(p) ? `(${typeToElm(p)})` : typeToElm(p)))
                .join(" ");
            return `${base} ${args}`;
        }
        case "Tuple":
            return `( ${t.elementTypes.map(typeToElm).join(", ")} )`;
        case "Record": {
            const fields = t.fieldTypes
                .map((f) => `${nameToCamel(f.name)} : ${typeToElm(f.tpe)}`)
                .join(", ");
            return fields ? `{ ${fields} }` : "{}";
        }
        case "ExtensibleRecord": {
            const varName = nameToCamel(t.variableName);
            const fields = t.fieldTypes
                .map((f) => `${nameToCamel(f.name)} : ${typeToElm(f.tpe)}`)
                .join(", ");
            return `{ ${varName} | ${fields} }`;
        }
        case "Function": {
            const arg = t.argumentType.kind === "Function"
                ? `(${typeToElm(t.argumentType)})`
                : typeToElm(t.argumentType);
            return `${arg} -> ${typeToElm(t.returnType)}`;
        }
    }
}

function typeDefToElm(typeName: Name, def: TypeDefinition<[]>): string {
    const name = nameToPascal(typeName);
    switch (def.kind) {
        case "TypeAliasDefinition": {
            const params = def.typeParams.map(nameToCamel).join(" ");
            const header = params ? `type alias ${name} ${params} =` : `type alias ${name} =`;
            return `${header}\n    ${typeToElm(def.typeExp)}`;
        }
        case "CustomTypeDefinition": {
            const params = def.typeParams.map(nameToCamel).join(" ");
            const header = params ? `type ${name} ${params}` : `type ${name}`;
            const ctors: string[] = [];
            for (const [ctorName, args] of def.ctors.value.entries()) {
                const argStr = args
                    .map(([, t]) =>
                        needsParens(t) ? `(${typeToElm(t)})` : typeToElm(t),
                    )
                    .join(" ");
                const ctor = nameToPascal(ctorName);
                ctors.push(argStr ? `${ctor} ${argStr}` : ctor);
            }
            if (ctors.length === 0) return header;
            return `${header}\n    = ${ctors.join("\n    | ")}`;
        }
    }
}

// ── Markdown generation ───────────────────────────────────────────────────────

function docParagraph(doc: string | null): string {
    if (!doc || !doc.trim()) return "";
    return doc.trim() + "\n\n";
}

export function generateModuleMarkdown(
    modulePath: Path,
    moduleDef: ModuleDefinition<[], Va>,
): string {
    const lines: string[] = [];

    const title = modulePath.map(nameToPascal).join(".");
    lines.push(`# ${title}\n`);

    const docPara = docParagraph(moduleDef.doc);
    if (docPara) lines.push(docPara);

    // ── Types ──
    const publicTypes: Array<[Name, Documented<TypeDefinition<[]>>]> = [];
    for (const [name, ac] of moduleDef.types.entries()) {
        if (ac.access.kind === "Public") {
            publicTypes.push([name, ac.value]);
        }
    }

    if (publicTypes.length > 0) {
        lines.push("## Types\n");
        for (const [name, documented] of publicTypes) {
            lines.push(`### ${nameToPascal(name)}\n`);
            const dp = docParagraph(documented.doc);
            if (dp) lines.push(dp);
            lines.push("```elm");
            lines.push(typeDefToElm(name, documented.value));
            lines.push("```\n");
        }
    }

    // ── Values ──
    const publicValues: Array<[Name, Documented<ValueDefinition<[], Va>>]> = [];
    for (const [name, ac] of moduleDef.values.entries()) {
        if (ac.access.kind === "Public") {
            publicValues.push([name, ac.value]);
        }
    }

    if (publicValues.length > 0) {
        lines.push("## Values\n");
        for (const [name, documented] of publicValues) {
            lines.push(`### ${nameToCamel(name)}\n`);
            const dp = docParagraph(documented.doc);
            if (dp) lines.push(dp);
            const def = documented.value;
            const inputTypes = def.inputTypes.map(([, , t]) =>
                t.kind === "Function" ? `(${typeToElm(t)})` : typeToElm(t),
            );
            const sig = [...inputTypes, typeToElm(def.outputType)].join(" -> ");
            lines.push("```elm");
            lines.push(`${nameToCamel(name)} : ${sig}`);
            lines.push("```\n");
        }
    }

    return lines.join("\n");
}

// ── Main entry point ──────────────────────────────────────────────────────────

export async function migrateFromMorphir(
    irFile: string,
    opts: MigrateFromMorphirOptions,
): Promise<MigrateFromMorphirResult> {
    const raw = await readFile(irFile, "utf8");
    const json: unknown = JSON.parse(raw);
    // IR files are wrapped in { formatVersion, distribution } since format v3.
    const distributionJson =
        json !== null &&
        typeof json === "object" &&
        "distribution" in (json as object)
            ? (json as { distribution: unknown }).distribution
            : json;
    const distribution = decodeDistribution(distributionJson);

    if (distribution.kind !== "Library") {
        throw new Error(`Unsupported distribution kind: ${distribution.kind}`);
    }

    const pkgSegment = pathToFileSegment(distribution.packageName);
    const files: MigratedFile[] = [];

    for (const [moduleName, acModuleDef] of distribution.packageDef.modules.entries()) {
        const modSegment = pathToFileSegment(moduleName);
        const relPath = `${pkgSegment}/${modSegment}.md`;
        const outPath = join(opts.output, relPath);
        const content = generateModuleMarkdown(
            moduleName,
            (acModuleDef as AccessControlled<ModuleDefinition<[], Va>>).value,
        );

        if (opts.dryRun) {
            files.push({ path: outPath, content, action: "dry-run" });
            continue;
        }

        if (existsSync(outPath) && !opts.overwrite) {
            files.push({ path: outPath, content, action: "skipped" });
            continue;
        }

        await mkdir(dirname(outPath), { recursive: true });
        await writeFile(outPath, content, "utf8");
        files.push({ path: outPath, content, action: "written" });
    }

    return { files };
}
