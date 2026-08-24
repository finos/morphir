/**
 * `substrate publish` — tag the current library commit and push the
 * tag to the origin remote.
 *
 * Aborts on corpus packages, since a corpus is not intended to be a
 * published dependency. Runs `substrate validate` first and aborts on
 * any failure.
 */
import { createAndPushTag, isWorkingTreeClean } from "../package/git.js";
import { locatePackage } from "../package/corpus.js";
import { validate } from "./validate.js";

export interface PublishResult {
    readonly root: string;
    readonly tag: string;
}

export async function publish(startDir: string): Promise<PublishResult> {
    const pkg = await locatePackage(startDir);

    if (pkg.manifest.kind === "corpus") {
        throw new Error(
            `Cannot publish corpus package "${pkg.manifest.name}"; ` +
                "corpora are not intended to be depended on.",
        );
    }
    if (pkg.manifest.version === undefined) {
        throw new Error(
            `Cannot publish: [package].version is not set in ${pkg.manifestPath}`,
        );
    }

    if (!(await isWorkingTreeClean(pkg.root))) {
        throw new Error(
            "Working tree is not clean; commit or stash changes before publishing.",
        );
    }

    const result = await validate(pkg.root);
    const errors = result.diagnostics.filter((d) => d.severity === "error");
    if (errors.length > 0) {
        throw new Error(
            `Validation failed with ${errors.length} error${errors.length === 1 ? "" : "s"}; ` +
                "fix reported issues and retry.",
        );
    }

    const tag = `v${pkg.manifest.version}`;
    await createAndPushTag(pkg.root, tag, `Release ${tag}`);
    return { root: pkg.root, tag };
}
