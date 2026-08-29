const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const Ajv = require("ajv");
const yaml = require("js-yaml");

const websiteRoot = path.dirname(__dirname);
const repositoryRoot = path.dirname(websiteRoot);
const formatVersionSpecPath = path.join(
	repositoryRoot,
	"docs/spec/ir/format-version.md",
);
const formatVersionCasesPath = path.join(
	repositoryRoot,
	"docs/spec/ir/fixtures/format-version-conformance.json",
);
const schemaRoot = path.join(websiteRoot, "static/schemas");
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

const U32_MAX = 4294967295n;
const RELEASE_PATTERN = /^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$/;
const SCHEMA_PROFILES = ["v1", "v2", "v3", "v4"];
const COMPATIBILITY_RESULTS = new Set([
	"supported",
	"unsupported_format_version_major",
	"unsupported_format_version_revision",
]);

function isPlainObject(value) {
	return value !== null && typeof value === "object" && !Array.isArray(value);
}

function schemaAcceptsOnly(testCase, acceptedProfile) {
	return SCHEMA_PROFILES.every(
		(profile) => testCase.schema[profile] === (profile === acceptedProfile),
	);
}

function allSchemasReject(testCase) {
	return SCHEMA_PROFILES.every((profile) => testCase.schema[profile] === false);
}

function normalizeFormatVersion(value) {
	if (typeof value === "number") {
		if (!Number.isInteger(value) || value < 0) {
			return { diagnostic: "invalid_format_version_type" };
		}
		if (value === 0) {
			return { diagnostic: "invalid_format_version_syntax" };
		}
		if (!Number.isSafeInteger(value) || BigInt(value) > U32_MAX) {
			return { diagnostic: "format_version_out_of_range" };
		}
		return { normalized: `${value}.0.0`, canonical: value };
	}
	if (typeof value !== "string") {
		return { diagnostic: "invalid_format_version_type" };
	}
	const matched = RELEASE_PATTERN.exec(value);
	if (matched === null) {
		return { diagnostic: "invalid_format_version_syntax" };
	}
	const components = matched.slice(1).map(BigInt);
	if (components[0] < 3n) {
		return { diagnostic: "invalid_format_version_syntax" };
	}
	if (components.some((component) => component > U32_MAX)) {
		return { diagnostic: "format_version_out_of_range" };
	}
	const [major, minor, patch] = components.map(Number);
	return {
		normalized: `${major}.${minor}.${patch}`,
		canonical: minor === 0 && patch === 0 ? major : value,
	};
}

function compatibility(normalized, supportedVersions) {
	const major = Number(normalized.split(".", 1)[0]);
	const supportedMajors = new Set(
		supportedVersions.map((version) => Number(version.split(".", 1)[0])),
	);
	if (!supportedMajors.has(major)) {
		return "unsupported_format_version_major";
	}
	return supportedVersions.includes(normalized)
		? "supported"
		: "unsupported_format_version_revision";
}

function scalarValidator(ajv, schema) {
	return ajv.compile({
		...schema.properties.formatVersion,
		definitions: schema.definitions,
	});
}

function parseRootDocument(testCase) {
	let parsed;
	switch (testCase.format) {
		case "json":
			parsed = JSON.parse(testCase.source);
			break;
		case "yaml":
			parsed = yaml.load(testCase.source, { json: false });
			break;
		default:
			assert.fail(`${testCase.name}: unknown header format ${testCase.format}`);
	}
	assert.ok(isPlainObject(parsed), `${testCase.name}: header must be a mapping`);
	return parsed;
}

function jsonRootMemberNames(source, caseName) {
	JSON.parse(source);
	const skipWhitespace = (start) => {
		let index = start;
		while (/\s/.test(source[index] ?? "")) {
			index += 1;
		}
		return index;
	};
	const skipString = (start) => {
		let index = start + 1;
		while (index < source.length) {
			if (source[index] === "\\") {
				index += 2;
			} else if (source[index] === '"') {
				return index + 1;
			} else {
				index += 1;
			}
		}
		assert.fail(`${caseName}: unterminated JSON string`);
	};

	let index = skipWhitespace(0);
	assert.equal(source[index], "{", `${caseName}: JSON root must be an object`);
	index += 1;
	let depth = 1;
	let expectsRootKey = true;
	const members = [];
	while (index < source.length) {
		index = skipWhitespace(index);
		if (depth === 1 && expectsRootKey) {
			if (source[index] === "}") {
				index = skipWhitespace(index + 1);
				assert.equal(index, source.length, `${caseName}: trailing JSON content`);
				return members;
			}
			assert.equal(source[index], '"', `${caseName}: JSON root key must be a string`);
			const keyEnd = skipString(index);
			const key = JSON.parse(source.slice(index, keyEnd));
			index = skipWhitespace(keyEnd);
			assert.equal(source[index], ":", `${caseName}: JSON root key must have a value`);
			members.push(key);
			expectsRootKey = false;
			index += 1;
			continue;
		}

		const character = source[index];
		if (character === '"') {
			index = skipString(index);
			continue;
		}
		if (character === "{" || character === "[") {
			depth += 1;
		} else if (character === "}" || character === "]") {
			depth -= 1;
			if (depth === 0) {
				index = skipWhitespace(index + 1);
				assert.equal(index, source.length, `${caseName}: trailing JSON content`);
				return members;
			}
		} else if (character === "," && depth === 1) {
			expectsRootKey = true;
		}
		index += 1;
	}
	assert.fail(`${caseName}: unterminated JSON root object`);
}

function yamlDocumentStart(source) {
	let index = source.charCodeAt(0) === 0xfeff ? 1 : 0;
	while (index < source.length) {
		while (/\s/.test(source[index] ?? "")) {
			index += 1;
		}
		if (source[index] === "#" || source[index] === "%") {
			index = source.indexOf("\n", index);
			if (index === -1) {
				return source.length;
			}
			continue;
		}
		if (
			source.startsWith("---", index) &&
			(source[index + 3] === undefined || /\s/.test(source[index + 3]))
		) {
			index += 3;
			continue;
		}
		return index;
	}
	return index;
}

function yamlQuotedScalarEnd(source, start, caseName) {
	const quote = source[start];
	let index = start + 1;
	while (index < source.length) {
		if (quote === '"' && source[index] === "\\") {
			index += 2;
		} else if (source[index] === quote) {
			if (quote === "'" && source[index + 1] === "'") {
				index += 2;
			} else {
				return index + 1;
			}
		} else {
			index += 1;
		}
	}
	assert.fail(`${caseName}: unterminated YAML quoted scalar`);
}

function decodeYamlKey(source, caseName) {
	const key = yaml.load(source, { json: true });
	assert.equal(typeof key, "string", `${caseName}: YAML root key must be a string`);
	return key;
}

function yamlMappingKey(source, start, end, caseName, flow) {
	let index = start;
	while (index < end && /[ \t]/.test(source[index])) {
		index += 1;
	}
	const keyStart = index;
	if (source[index] === "'" || source[index] === '"') {
		index = yamlQuotedScalarEnd(source, index, caseName);
		assert.ok(index <= end, `${caseName}: multiline YAML keys are not supported`);
	} else {
		while (
			index < end &&
			!(
				source[index] === ":" &&
				(flow || index + 1 >= end || /[ \t#]/.test(source[index + 1]))
			)
		) {
			index += 1;
		}
	}
	const keyEnd = index;
	while (index < end && /[ \t]/.test(source[index])) {
		index += 1;
	}
	assert.equal(source[index], ":", `${caseName}: YAML root key must have a value`);
	const keySource = source.slice(keyStart, keyEnd).trim();
	assert.ok(keySource !== "", `${caseName}: YAML root key must not be empty`);
	return {
		key: decodeYamlKey(keySource, caseName),
		style:
			keySource[0] === "'"
				? "single-quoted"
				: keySource[0] === '"'
					? "double-quoted"
					: "plain",
		valueStart: index + 1,
	};
}

function isYamlCommentStart(source, index) {
	return source[index] === "#" &&
		(index === 0 || /\s/.test(source[index - 1]));
}

function scanYamlValueLine(source, start, end, state, caseName) {
	let index = start;
	while (index < end) {
		if (isYamlCommentStart(source, index)) {
			return;
		}
		if (source[index] === "'" || source[index] === '"') {
			const quoteEnd = yamlQuotedScalarEnd(source, index, caseName);
			if (quoteEnd > end) {
				state.quotedUntil = quoteEnd;
				return;
			}
			index = quoteEnd;
			continue;
		}
		if (source[index] === "{" || source[index] === "[") {
			state.flowDepth += 1;
		} else if (source[index] === "}" || source[index] === "]") {
			state.flowDepth -= 1;
			assert.ok(state.flowDepth >= 0, `${caseName}: invalid YAML flow nesting`);
		}
		index += 1;
	}
}

function scanYamlBlockValue(source, start, end, state, caseName) {
	let valueStart = start;
	while (valueStart < end && /[ \t]/.test(source[valueStart])) {
		valueStart += 1;
	}
	if (
		source[valueStart] === "'" ||
		source[valueStart] === '"' ||
		source[valueStart] === "{" ||
		source[valueStart] === "["
	) {
		scanYamlValueLine(source, valueStart, end, state, caseName);
	}
}

function yamlBlockRootMemberNames(source, start, caseName, keyStyles) {
	const members = [];
	const state = { flowDepth: 0, quotedUntil: 0, blockScalarIndent: null };
	let lineStart = start;
	while (lineStart < source.length) {
		const newline = source.indexOf("\n", lineStart);
		const lineEnd = newline === -1 ? source.length : newline;
		const line = source.slice(lineStart, lineEnd).replace(/\r$/, "");
		const indent = /^[ ]*/.exec(line)[0].length;
		const trimmed = line.slice(indent);

		if (state.quotedUntil > lineStart) {
			if (state.quotedUntil <= lineEnd) {
				const quotedEnd = state.quotedUntil;
				state.quotedUntil = 0;
				scanYamlValueLine(source, quotedEnd, lineEnd, state, caseName);
			}
			lineStart = newline === -1 ? source.length : newline + 1;
			continue;
		}
		state.quotedUntil = 0;
		if (state.blockScalarIndent !== null) {
			if (trimmed === "" || indent > state.blockScalarIndent) {
				lineStart = newline === -1 ? source.length : newline + 1;
				continue;
			}
			state.blockScalarIndent = null;
		}
		if (
			trimmed === "" ||
			trimmed.startsWith("#") ||
			trimmed === "---" ||
			trimmed === "..."
		) {
			lineStart = newline === -1 ? source.length : newline + 1;
			continue;
		}
		if (state.flowDepth > 0) {
			scanYamlValueLine(source, lineStart + indent, lineEnd, state, caseName);
			lineStart = newline === -1 ? source.length : newline + 1;
			continue;
		}
		if (indent > 0) {
			lineStart = newline === -1 ? source.length : newline + 1;
			continue;
		}

		const entry = yamlMappingKey(source, lineStart, lineEnd, caseName, false);
		members.push(entry.key);
		keyStyles.push(entry.style);
		const value = source.slice(entry.valueStart, lineEnd).trim();
		if (/^[|>][0-9+-]*(?:\s+#.*)?$/.test(value)) {
			state.blockScalarIndent = indent;
		} else {
			scanYamlBlockValue(source, entry.valueStart, lineEnd, state, caseName);
		}
		lineStart = newline === -1 ? source.length : newline + 1;
	}
	assert.equal(state.flowDepth, 0, `${caseName}: unterminated YAML flow value`);
	return members;
}

function yamlFlowRootMemberNames(source, start, caseName, keyStyles) {
	const members = [];
	let index = start + 1;
	let depth = 1;
	let expectsKey = true;
	while (index < source.length) {
		if (/\s/.test(source[index])) {
			index += 1;
			continue;
		}
		if (isYamlCommentStart(source, index)) {
			const newline = source.indexOf("\n", index);
			index = newline === -1 ? source.length : newline + 1;
			continue;
		}
		if (depth === 1 && expectsKey) {
			if (source[index] === "}") {
				return members;
			}
			const entry = yamlMappingKey(source, index, source.length, caseName, true);
			members.push(entry.key);
			keyStyles.push(entry.style);
			index = entry.valueStart;
			expectsKey = false;
			continue;
		}
		if (source[index] === "'" || source[index] === '"') {
			index = yamlQuotedScalarEnd(source, index, caseName);
			continue;
		}
		if (source[index] === "{" || source[index] === "[") {
			depth += 1;
		} else if (source[index] === "}" || source[index] === "]") {
			depth -= 1;
			if (depth === 0) {
				return members;
			}
		} else if (source[index] === "," && depth === 1) {
			expectsKey = true;
		}
		index += 1;
	}
	assert.fail(`${caseName}: unterminated YAML flow mapping`);
}

function yamlRootMemberNames(source, caseName, keyStyles = []) {
	const parsed = yaml.load(source, { json: true });
	assert.ok(isPlainObject(parsed), `${caseName}: YAML root must be a mapping`);
	const start = yamlDocumentStart(source);
	return source[start] === "{"
		? yamlFlowRootMemberNames(source, start, caseName, keyStyles)
		: yamlBlockRootMemberNames(source, start, caseName, keyStyles);
}

function rawRootMemberNames(testCase, keyStyles = []) {
	switch (testCase.format) {
		case "json":
			return jsonRootMemberNames(testCase.source, testCase.name);
		case "yaml":
			return yamlRootMemberNames(testCase.source, testCase.name, keyStyles);
		default:
			assert.fail(`${testCase.name}: unknown root diagnostic format ${testCase.format}`);
	}
}

function assertNamedCases(cases, section) {
	assert.ok(Array.isArray(cases), `${section} must be an array`);
	assert.ok(cases.length > 0, `${section} must not be empty`);
	const names = cases.map((testCase) => {
		assert.ok(isPlainObject(testCase), `${section} entries must be objects`);
		assert.ok(
			typeof testCase.name === "string" && testCase.name.trim() !== "",
			`${section} entries must have names`,
		);
		return testCase.name;
	});
	assert.equal(new Set(names).size, names.length, `${section} names must be unique`);
}

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

assert.ok(
	fs.existsSync(formatVersionSpecPath),
	"missing shared formatVersion specification",
);
assert.ok(
	fs.existsSync(formatVersionCasesPath),
	"missing formatVersion conformance cases",
);

const conformance = JSON.parse(fs.readFileSync(formatVersionCasesPath, "utf8"));
assert.ok(isPlainObject(conformance), "formatVersion conformance corpus must be an object");
assert.equal(conformance.contractVersion, 1, "formatVersion conformance contractVersion");
assertNamedCases(conformance.scalarCases, "scalarCases");
assertNamedCases(conformance.headerOrderCases, "headerOrderCases");
assertNamedCases(conformance.rootDiagnosticCases, "rootDiagnosticCases");
const supportedVersions = conformance.supportedVersions;
assert.deepEqual(
	supportedVersions,
	["3.0.0", "4.0.0"],
	"supported exact format versions",
);

const normalizedScalarCases = conformance.scalarCases.map((testCase) => {
	assert.ok(isPlainObject(testCase.normalization), `${testCase.name}: normalization`);
	assert.ok(
		Object.hasOwn(testCase, "compatibility"),
		`${testCase.name}: missing compatibility expectation`,
	);
	assert.ok(isPlainObject(testCase.schema), `${testCase.name}: schema expectations`);
	assert.deepEqual(
		Object.keys(testCase.schema).sort(),
		SCHEMA_PROFILES,
		`${testCase.name}: schema profiles`,
	);
	for (const profile of SCHEMA_PROFILES) {
		assert.equal(
			typeof testCase.schema[profile],
			"boolean",
			`${testCase.name}: ${profile} schema expectation`,
		);
	}
	const hasDiagnostic = Object.hasOwn(testCase.normalization, "diagnostic");
	const hasNormalized = Object.hasOwn(testCase.normalization, "normalized");
	assert.notEqual(
		hasDiagnostic,
		hasNormalized,
		`${testCase.name}: normalization must contain either diagnostic or normalized`,
	);
	if (hasDiagnostic) {
		assert.deepEqual(
			Object.keys(testCase.normalization),
			["diagnostic"],
			`${testCase.name}: diagnostic normalization shape`,
		);
		assert.equal(
			testCase.compatibility,
			null,
			`${testCase.name}: diagnostic compatibility`,
		);
	} else {
		assert.deepEqual(
			Object.keys(testCase.normalization).sort(),
			["canonical", "normalized"],
			`${testCase.name}: successful normalization shape`,
		);
		assert.ok(
			COMPATIBILITY_RESULTS.has(testCase.compatibility),
			`${testCase.name}: compatibility result`,
		);
	}
	return {
		testCase,
		actual: normalizeFormatVersion(testCase.value),
	};
});

const supportedMajors = new Set(
	supportedVersions.map((version) => Number(version.split(".", 1)[0])),
);
const requiredScalarCoverage = new Map([
	[
		"release string with a plus sign",
		({ testCase }) =>
			typeof testCase.value === "string" &&
			/(^|\.)\+[0-9]/.test(testCase.value),
	],
	[
		"release string with a minus sign",
		({ testCase }) =>
			typeof testCase.value === "string" &&
			/(^|\.)-[0-9]/.test(testCase.value),
	],
	[
		"release string containing whitespace",
		({ testCase }) =>
			typeof testCase.value === "string" && /\s/.test(testCase.value),
	],
	[
		"forbidden v1 release string alias",
		({ actual, testCase }) =>
			testCase.value === "1.0.0" &&
			actual.diagnostic === "invalid_format_version_syntax" &&
			testCase.compatibility === null &&
			allSchemasReject(testCase),
	],
	[
		"forbidden v2 release string alias",
		({ actual, testCase }) =>
			testCase.value === "2.0.0" &&
			actual.diagnostic === "invalid_format_version_syntax" &&
			testCase.compatibility === null &&
			allSchemasReject(testCase),
	],
	[
		"unrecognized integer zero",
		({ actual, testCase }) =>
			testCase.value === 0 &&
			actual.diagnostic === "invalid_format_version_syntax" &&
			testCase.compatibility === null &&
			allSchemasReject(testCase),
	],
	[
		"valid-family release string with a leading-zero minor",
		({ testCase }) =>
			typeof testCase.value === "string" &&
			/^([1-9][0-9]*)\.0[0-9]+\.(0|[1-9][0-9]*)$/.test(testCase.value) &&
			supportedMajors.has(Number(testCase.value.split(".", 1)[0])),
	],
	[
		"valid-family release string with a leading-zero patch",
		({ testCase }) =>
			typeof testCase.value === "string" &&
			/^([1-9][0-9]*)\.(0|[1-9][0-9]*)\.0[0-9]+$/.test(testCase.value) &&
			supportedMajors.has(Number(testCase.value.split(".", 1)[0])),
	],
	[
		"release string with a missing component",
		({ testCase }) =>
			typeof testCase.value === "string" &&
			/^\d+\.\d+$/.test(testCase.value),
	],
	[
		"release string with an extra component",
		({ testCase }) =>
			typeof testCase.value === "string" &&
			/^\d+\.\d+\.\d+\.\d+$/.test(testCase.value),
	],
	[
		"prerelease suffix",
		({ testCase }) =>
			typeof testCase.value === "string" &&
			/^\d+\.\d+\.\d+-/.test(testCase.value),
	],
	[
		"build metadata",
		({ testCase }) =>
			typeof testCase.value === "string" &&
			/^\d+\.\d+\.\d+\+/.test(testCase.value),
	],
	["boolean value", ({ testCase }) => typeof testCase.value === "boolean"],
	["null value", ({ testCase }) => testCase.value === null],
	["array value", ({ testCase }) => Array.isArray(testCase.value)],
	[
		"object value",
		({ testCase }) => isPlainObject(testCase.value),
	],
	[
		"non-integer number",
		({ testCase }) =>
			typeof testCase.value === "number" &&
			!Number.isInteger(testCase.value),
	],
	[
		"integer u32 overflow",
		({ testCase }) =>
			typeof testCase.value === "number" &&
			Number.isInteger(testCase.value) &&
			(!Number.isSafeInteger(testCase.value) || BigInt(testCase.value) > U32_MAX) &&
			allSchemasReject(testCase),
	],
	[
		"release component u32 overflow",
		({ actual, testCase }) =>
			typeof testCase.value === "string" &&
			/^\d+\.\d+\.\d+$/.test(testCase.value) &&
			testCase.value.split(".").some((component) => BigInt(component) > U32_MAX) &&
			actual.diagnostic === "format_version_out_of_range" &&
			schemaAcceptsOnly(testCase, `v${testCase.value.split(".", 1)[0]}`),
	],
	[
		"future major family release string",
		({ actual, testCase }) =>
			typeof testCase.value === "string" &&
			actual.normalized !== undefined &&
			Number(actual.normalized.split(".", 1)[0]) >= 3 &&
			!supportedMajors.has(Number(actual.normalized.split(".", 1)[0])) &&
			testCase.compatibility === "unsupported_format_version_major" &&
			allSchemasReject(testCase),
	],
	[
		"future major family integer alias",
		({ actual, testCase }) =>
			typeof testCase.value === "number" &&
			Number.isInteger(testCase.value) &&
			actual.normalized !== undefined &&
			Number(actual.normalized.split(".", 1)[0]) >= 3 &&
			!supportedMajors.has(Number(actual.normalized.split(".", 1)[0])) &&
			testCase.compatibility === "unsupported_format_version_major" &&
			allSchemasReject(testCase),
	],
	[
		"future nonbaseline exact release",
		({ actual, testCase }) =>
			typeof testCase.value === "string" &&
			actual.normalized === testCase.value &&
			actual.canonical === testCase.value &&
			!testCase.value.endsWith(".0.0") &&
			!supportedMajors.has(Number(testCase.value.split(".", 1)[0])) &&
			testCase.compatibility === "unsupported_format_version_major" &&
			allSchemasReject(testCase),
	],
	[
		"maximum u32 major release string",
		({ actual, testCase }) =>
			testCase.value === `${U32_MAX}.0.0` &&
			actual.normalized === testCase.value &&
			actual.canonical === Number(U32_MAX) &&
			testCase.compatibility === "unsupported_format_version_major" &&
			allSchemasReject(testCase),
	],
	[
		"overflowing major release string",
		({ actual, testCase }) =>
			testCase.value === `${U32_MAX + 1n}.0.0` &&
			actual.diagnostic === "format_version_out_of_range" &&
			testCase.compatibility === null &&
			allSchemasReject(testCase),
	],
	[
		"maximum u32 integer boundary",
		({ actual, testCase }) =>
			testCase.value === Number(U32_MAX) &&
			actual.normalized === `${U32_MAX}.0.0` &&
			actual.canonical === Number(U32_MAX) &&
			testCase.compatibility === "unsupported_format_version_major" &&
			allSchemasReject(testCase),
	],
	[
		"same-major unsupported revision",
		({ actual, testCase }) =>
			actual.normalized !== undefined &&
			supportedMajors.has(Number(actual.normalized.split(".", 1)[0])) &&
			!supportedVersions.includes(actual.normalized) &&
			testCase.compatibility === "unsupported_format_version_revision",
	],
	[
		"valid nonbaseline revision preserving its exact canonical string",
		({ actual, testCase }) =>
			typeof testCase.value === "string" &&
			actual.normalized === testCase.value &&
			actual.canonical === testCase.value &&
			Number(testCase.value.split(".", 1)[0]) >= 3 &&
			supportedMajors.has(Number(testCase.value.split(".", 1)[0])) &&
			!testCase.value.endsWith(".0.0") &&
			schemaAcceptsOnly(testCase, `v${testCase.value.split(".", 1)[0]}`),
	],
]);

for (const [coverage, predicate] of requiredScalarCoverage) {
	assert.ok(
		normalizedScalarCases.some(predicate),
		`missing named scalar case covering ${coverage}`,
	);
}
for (const { testCase } of normalizedScalarCases) {
	if (
		testCase.normalization.diagnostic === "invalid_format_version_syntax" ||
		testCase.normalization.diagnostic === "invalid_format_version_type"
	) {
		assert.ok(
			allSchemasReject(testCase),
			`${testCase.name}: malformed values must be rejected by every schema`,
		);
	}
}
for (const historicalMajor of [1, 2]) {
	assert.ok(
		normalizedScalarCases.some(
			({ actual, testCase }) =>
				testCase.value === historicalMajor &&
				actual.normalized === `${historicalMajor}.0.0` &&
				actual.canonical === historicalMajor &&
				testCase.compatibility === "unsupported_format_version_major" &&
				schemaAcceptsOnly(testCase, `v${historicalMajor}`),
		),
		`missing named scalar case covering historical integer v${historicalMajor}`,
	);
}
for (const supportedVersion of supportedVersions) {
	const [major, minor, patch] = supportedVersion.split(".").map(Number);
	assert.equal(minor, 0, `${supportedVersion}: supported integer alias minor`);
	assert.equal(patch, 0, `${supportedVersion}: supported integer alias patch`);
	const expected = { normalized: supportedVersion, canonical: major };
	assert.ok(
		normalizedScalarCases.some(
			({ actual, testCase }) =>
				testCase.value === major &&
				actual.normalized === expected.normalized &&
				actual.canonical === expected.canonical &&
				testCase.compatibility === "supported" &&
				schemaAcceptsOnly(testCase, `v${major}`),
		),
		`missing named scalar case covering integer alias ${major}`,
	);
	assert.ok(
		normalizedScalarCases.some(
			({ actual, testCase }) =>
				testCase.value === supportedVersion &&
				actual.normalized === expected.normalized &&
				actual.canonical === expected.canonical &&
				testCase.compatibility === "supported" &&
				schemaAcceptsOnly(testCase, `v${major}`),
		),
		`missing named scalar case covering exact baseline spelling ${supportedVersion}`,
	);
	assert.ok(
		normalizedScalarCases.some(
			({ actual, testCase }) =>
				typeof testCase.value === "string" &&
				actual.normalized === testCase.value &&
				actual.normalized.startsWith(`${major}.`) &&
				actual.normalized !== supportedVersion &&
				actual.canonical === testCase.value &&
				testCase.compatibility === "unsupported_format_version_revision" &&
				schemaAcceptsOnly(testCase, `v${major}`),
		),
		`missing named scalar case covering valid later v${major} revision`,
	);
	assert.ok(
		normalizedScalarCases.some(
			({ actual, testCase }) =>
				typeof testCase.value === "string" &&
				testCase.value.startsWith(`${major}.`) &&
				/^\d+\.\d+\.\d+$/.test(testCase.value) &&
				testCase.value
					.split(".")
					.some((component) => BigInt(component) > U32_MAX) &&
				actual.diagnostic === "format_version_out_of_range" &&
				testCase.compatibility === null &&
				schemaAcceptsOnly(testCase, `v${major}`),
		),
		`missing named scalar case covering v${major} string component overflow`,
	);
}

for (const { testCase, actual } of normalizedScalarCases) {
	assert.deepEqual(actual, testCase.normalization, testCase.name);
	if (actual.normalized !== undefined) {
		assert.equal(
			compatibility(actual.normalized, supportedVersions),
			testCase.compatibility,
			`${testCase.name}: compatibility`,
		);
	}
}

const ajv = new Ajv({ allErrors: true, strict: false });
const schemas = Object.fromEntries(
	[1, 2, 3, 4].map((version) => [
		`v${version}`,
		JSON.parse(
			fs.readFileSync(
				path.join(schemaRoot, `morphir-ir-v${version}.json`),
				"utf8",
			),
		),
	]),
);
const validators = Object.fromEntries(
	Object.entries(schemas).map(([profile, schema]) => [
		profile,
		scalarValidator(ajv, schema),
	]),
);
const fullProfileValidators = Object.fromEntries(
	Object.entries(schemas).map(([profile, schema]) => [
		profile,
		ajv.compile(schema),
	]),
);

assert.equal(validators.v1(1), true, "v1 schema accepts integer 1");
assert.equal(validators.v1("1.0.0"), false, "v1 schema rejects release strings");
assert.equal(validators.v2(2), true, "v2 schema accepts integer 2");
assert.equal(validators.v2("2.0.0"), false, "v2 schema rejects release strings");

for (const testCase of conformance.scalarCases) {
	for (const profile of SCHEMA_PROFILES) {
		assert.equal(
			validators[profile](testCase.value),
			testCase.schema[profile],
			`${testCase.name}: ${profile} schema`,
		);
	}
}

const headerOrderCoverage = new Set();
for (const testCase of conformance.headerOrderCases) {
	assert.equal(typeof testCase.source, "string", `${testCase.name}: source`);
	assert.ok(Array.isArray(testCase.members), `${testCase.name}: members`);
	assert.ok(
		testCase.warning === null ||
			testCase.warning === "format_version_not_first",
		`${testCase.name}: warning expectation`,
	);
	const parsedRoot = parseRootDocument(testCase);
	const members = Object.keys(parsedRoot);
	assert.deepEqual(members, testCase.members, `${testCase.name}: members`);
	const normalized = normalizeFormatVersion(parsedRoot.formatVersion);
	assert.ok(normalized.normalized, `${testCase.name}: valid root formatVersion`);
	const profile = `v${normalized.normalized.split(".", 1)[0]}`;
	assert.ok(
		Object.hasOwn(fullProfileValidators, profile),
		`${testCase.name}: unknown full schema profile ${profile}`,
	);
	const fullProfileValidator = fullProfileValidators[profile];
	assert.equal(
		fullProfileValidator(parsedRoot),
		true,
		`${testCase.name}: ${profile} full schema ${JSON.stringify(fullProfileValidator.errors)}`,
	);
	if (testCase.warning === null) {
		assert.deepEqual(
			members.slice(0, 2),
			["formatVersion", "distribution"],
			`${testCase.name}: canonical header members`,
		);
		headerOrderCoverage.add(`${testCase.format}:canonical`);
	} else {
		assert.deepEqual(
			members.slice(0, 2),
			["distribution", "formatVersion"],
			`${testCase.name}: noncanonical header members`,
		);
		headerOrderCoverage.add(`${testCase.format}:noncanonical`);
	}
	assert.equal(
		members[0] === "formatVersion" ? null : "format_version_not_first",
		testCase.warning,
		`${testCase.name}: warning`,
	);
}
assert.deepEqual(
	[...headerOrderCoverage].sort(),
	["json:canonical", "json:noncanonical", "yaml:canonical", "yaml:noncanonical"],
	"headerOrderCases must cover canonical and noncanonical JSON and YAML",
);

const flowExtractorKeyStyles = [];
assert.deepEqual(
	yamlRootMemberNames(
		"value: brace { text\nfollowing: present\n",
		"YAML block plain scalar containing brace",
	),
	["value", "following"],
	"YAML block brace plain scalar root members",
);
assert.deepEqual(
	yamlRootMemberNames(
		"value: bracket [ text\nfollowing: present\n",
		"YAML block plain scalar containing bracket",
	),
	["value", "following"],
	"YAML block bracket plain scalar root members",
);
assert.deepEqual(
	yamlRootMemberNames(
		"{ value: foo#bar, following: present }",
		"YAML flow plain scalar containing hash",
	),
	["value", "following"],
	"YAML flow hash plain scalar root members",
);
assert.deepEqual(
	yamlRootMemberNames(
		'{ "formatVersion": 3, nested: { formatVersion: 4 }, note: "distribution: not a key", \'distribution\': {} }',
		"YAML flow root extractor",
		flowExtractorKeyStyles,
	),
	["formatVersion", "nested", "note", "distribution"],
	"YAML flow root extractor members",
);
assert.deepEqual(
	flowExtractorKeyStyles,
	["double-quoted", "plain", "plain", "single-quoted"],
	"YAML flow root extractor key styles",
);

const rootDiagnosticCoverage = new Set();
let hasQuotedYamlDuplicate = false;
for (const testCase of conformance.rootDiagnosticCases) {
	assert.equal(typeof testCase.source, "string", `${testCase.name}: source`);
	assert.ok(Array.isArray(testCase.members), `${testCase.name}: members`);
	assert.ok(
		testCase.diagnostic === "missing_format_version" ||
			testCase.diagnostic === "duplicate_format_version",
		`${testCase.name}: diagnostic`,
	);
	const keyStyles = [];
	const members = rawRootMemberNames(testCase, keyStyles);
	assert.deepEqual(members, testCase.members, `${testCase.name}: root members`);
	const formatVersionCount = members.filter(
		(member) => member === "formatVersion",
	).length;
	const diagnostic =
		formatVersionCount === 0
			? "missing_format_version"
			: formatVersionCount > 1
				? "duplicate_format_version"
				: null;
	assert.equal(diagnostic, testCase.diagnostic, `${testCase.name}: derived diagnostic`);
	if (testCase.format === "yaml" && diagnostic === "duplicate_format_version") {
		const formatVersionStyles = members.flatMap((member, index) =>
			member === "formatVersion" ? [keyStyles[index]] : [],
		);
		if (
			formatVersionStyles.includes("single-quoted") &&
			formatVersionStyles.includes("double-quoted")
		) {
			hasQuotedYamlDuplicate = true;
		}
	}
	rootDiagnosticCoverage.add(`${testCase.format}:${diagnostic}`);
}
assert.ok(
	hasQuotedYamlDuplicate,
	"rootDiagnosticCases must cover single- and double-quoted duplicate YAML formatVersion keys",
);
assert.deepEqual(
	[...rootDiagnosticCoverage].sort(),
	[
		"json:duplicate_format_version",
		"json:missing_format_version",
		"yaml:duplicate_format_version",
		"yaml:missing_format_version",
	],
	"rootDiagnosticCases must cover missing and duplicate versions in JSON and YAML",
);

console.log("IR storage profile checks passed");
