// Assertions on website/static/schemas/morphir-ir-v4.json, run through the official jsonschema CLI.
//
// tests/fixtures/morphir-ir-v4-schema holds the cases, in the {target, tests} form of tools/jsonschema-fixtures.ts.
// package-definition-modules.json checks that a package's modules are validated inside in each accepted spelling:
// the access level as the key, the legacy { access, value }, and the flattened { access, types, values, doc }.
import { expect, test } from "bun:test";
import path from "node:path";

import { runFixtureSuite } from "./jsonschema-fixtures.ts";

const root = path.resolve(import.meta.dir, "..");

test("the v4 schema validates a module's contents in every accepted spelling", async () => {
	const count = await runFixtureSuite(path.join(root, "tests/fixtures/morphir-ir-v4-schema"), ["-r", path.join(root, "website/static/schemas/morphir-ir-v4.json")]);
	expect(count).toBeGreaterThan(0);
}, 120_000);
