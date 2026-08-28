const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const yaml = require("js-yaml");

const websiteRoot = path.dirname(__dirname);
const repositoryRoot = path.dirname(websiteRoot);
const v4SpecRoot = path.join(repositoryRoot, "docs/spec/ir/schemas/v4");
const fixtureRoot = path.join(
	repositoryRoot,
	"crates/morphir/tests/fixtures/migrate/yaml",
);

const requiredSections = new Map([
	[
		"semantic-model.md",
		["# V4 Semantic IR Model", "Logical document identities"],
	],
	[
		"json-profile.md",
		["# V4 JSON Serialization Profile", "JSON Schema bootstrap"],
	],
	[
		"yaml-profile.md",
		[
			"# V4 YAML Serialization Profile",
			"Explicit structural vocabulary",
			"Readable vocabulary",
		],
	],
	[
		"document-tree-files.md",
		["Serialization profile", "manifest.yaml", "manifest.json"],
	],
]);

for (const [fileName, headings] of requiredSections) {
	const filePath = path.join(v4SpecRoot, fileName);
	assert.ok(fs.existsSync(filePath), `missing v4 IR profile: ${fileName}`);
	const source = fs.readFileSync(filePath, "utf8");
	for (const heading of headings) {
		assert.ok(
			source.includes(heading),
			`${fileName} is missing required section: ${heading}`,
		);
	}
}

for (const fileName of [
	"v3-explicit.yaml",
	"v4-explicit.yaml",
	"v4-readable.yaml",
]) {
	const filePath = path.join(fixtureRoot, fileName);
	assert.ok(fs.existsSync(filePath), `missing normative YAML fixture: ${fileName}`);
	const documents = [];
	yaml.loadAll(
		fs.readFileSync(filePath, "utf8"),
		(document) => documents.push(document),
		{ json: false },
	);
	assert.equal(documents.length, 1, `${fileName} must contain one YAML document`);
	assert.ok(
		documents[0] !== null &&
			typeof documents[0] === "object" &&
			!Array.isArray(documents[0]),
		`${fileName} must contain a mapping at its root`,
	);
}

console.log("IR storage profile checks passed");
