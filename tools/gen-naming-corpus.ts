// Generates docs/spec/ir/fixtures/naming-conformance.json, the shared conformance
// corpus for Morphir IR v4 name canonicalization.
//
//   bun run gen-naming-corpus.ts            # write the corpus
//   bun run gen-naming-corpus.ts --check    # verify it and its vendored copy
//
// Per kb decision 0003 this generator is expected to be replaced by a Morphir
// model of the naming codec, at which point the corpus becomes a build output of
// that model.
import { existsSync, readFileSync, writeFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const toolsRoot = path.dirname(fileURLToPath(import.meta.url));
const repositoryRoot = path.dirname(toolsRoot);
const corpusPath = path.join(
	repositoryRoot,
	"docs/spec/ir/fixtures/naming-conformance.json",
);
const vendoredPath = path.join(
	repositoryRoot,
	"ecosystem/morphir-rust/tests/fixtures/naming-conformance.json",
);

// ---------------------------------------------------------------- model

/** A segment is an ordinary word or an initialism. Text is always lowercase. */
type SegmentKind = "word" | "initialism";
interface Segment {
	readonly kind: SegmentKind;
	readonly text: string;
}

/** Which canonical encoding a string is written in. */
type Style = "uppercase" | "doubledHyphen";
type Canonical = Readonly<Record<Style, string>>;

interface Rendered {
	readonly camelCase: string;
	readonly pascalCaseUpperInitialism: string;
	readonly pascalCasePascalInitialism: string;
	readonly snakeCase: string;
	readonly kebabCase: string;
	readonly screamingSnakeCase: string;
}

interface RoundTripCase {
	readonly name: string;
	readonly segments: readonly Segment[];
	readonly canonical: Canonical;
	readonly escapedStem: string;
	readonly rendered: Rendered;
	readonly legacyArray?: readonly string[];
}

interface LegacyDecodeCase {
	readonly legacyArray: readonly string[];
	readonly segments: readonly Segment[];
	readonly canonical: Canonical;
}

interface RejectCase {
	readonly input: string;
	readonly validAs: Readonly<Record<Style, boolean>>;
}

interface PathCase {
	readonly canonical: Canonical;
	readonly escapedPath: string;
}

interface FqNameCase {
	readonly canonical: Canonical;
	readonly documentTreePath: string;
}

interface Corpus {
	readonly contractVersion: number;
	readonly description: string;
	readonly styles: readonly Style[];
	readonly shippedStyle: Style;
	readonly notes: readonly string[];
	readonly patterns: {
		readonly name: Readonly<Record<Style, string>>;
		readonly fileStem: string;
	};
	readonly reservedDeviceStems: readonly string[];
	readonly roundTripCases: readonly RoundTripCase[];
	readonly legacyDecodeCases: readonly LegacyDecodeCase[];
	readonly rejectCases: readonly RejectCase[];
	readonly pathCases: readonly PathCase[];
	readonly fqNameCases: readonly FqNameCase[];
}

/** A Name is a non-empty sequence of segments. */
type Name = readonly Segment[];
/** A Path is a sequence of Names. */
type NamePath = readonly Name[];

// ---------------------------------------------------------------- codec

const RESERVED: readonly string[] = [
	"con",
	"prn",
	"aux",
	"nul",
	...Array.from({ length: 10 }, (_, i) => `com${i}`),
	...Array.from({ length: 10 }, (_, i) => `lpt${i}`),
];
const RESERVED_SET = new Set(RESERVED);

const w = (text: string): Segment => ({ kind: "word", text });
const i = (text: string): Segment => ({ kind: "initialism", text });

const P_UP = "^([a-z0-9]+|[A-Z0-9]+)(-([a-z0-9]+|[A-Z0-9]+))*$";
const P_DB = "^(--)?[a-z0-9]+(--?[a-z0-9]+)*$";
const P_ST = "^_?[a-z0-9]+(-_?[a-z0-9]+)*_?$";

const encUpper = (segs: Name): string =>
	segs
		.map((s) => (s.kind === "initialism" ? s.text.toUpperCase() : s.text))
		.join("-");

const encDouble = (segs: Name): string =>
	segs
		.map((s, n) => (s.kind === "initialism" ? "--" : n > 0 ? "-" : "") + s.text)
		.join("");

const escapeName = (segs: Name): string => {
	const stem = segs
		.map((s) => (s.kind === "initialism" ? `_${s.text}` : s.text))
		.join("-");
	return RESERVED_SET.has(stem.toLowerCase()) ? `${stem}_` : stem;
};

const title = (s: string): string =>
	s ? s[0]!.toUpperCase() + s.slice(1) : "";

const render = (segs: Name): Rendered => ({
	camelCase: segs
		.map((s, n) =>
			n === 0
				? s.text
				: s.kind === "initialism"
					? s.text.toUpperCase()
					: title(s.text),
		)
		.join(""),
	pascalCaseUpperInitialism: segs
		.map((s) => (s.kind === "initialism" ? s.text.toUpperCase() : title(s.text)))
		.join(""),
	pascalCasePascalInitialism: segs.map((s) => title(s.text)).join(""),
	snakeCase: segs.map((s) => s.text).join("_"),
	kebabCase: segs.map((s) => s.text).join("-"),
	screamingSnakeCase: segs.map((s) => s.text.toUpperCase()).join("_"),
});

/**
 * Decision 0001: a maximal run of two or more single-letter words collapses to
 * one initialism; a run of one stays a word.
 */
const legacyDecode = (words: readonly string[]): Segment[] => {
	const out: Segment[] = [];
	let run: string[] = [];
	const flush = (): void => {
		if (run.length >= 2) out.push(i(run.join("")));
		else if (run.length === 1) out.push(w(run[0]!));
		run = [];
	};
	for (const word of words) {
		if (word.length === 1) run.push(word);
		else {
			flush();
			out.push(w(word));
		}
	}
	flush();
	return out;
};

const pathStr = (names: NamePath, fn: (segs: Name) => string): string =>
	names.map(fn).join("/");

// ---------------------------------------------------------------- cases

interface RoundTripSpec {
	readonly name: string;
	readonly segs: Name;
	readonly legacy?: readonly string[];
}

const ROUND_TRIP: readonly RoundTripSpec[] = [
	{ name: "plain two-word name", segs: [w("user"), w("account")], legacy: ["user", "account"] },
	{ name: "trailing initialism", segs: [w("value"), w("in"), i("usd")], legacy: ["value", "in", "u", "s", "d"] },
	{ name: "word that looks like an initialism", segs: [w("in"), w("usd")], legacy: ["in", "usd"] },
	{ name: "initialism at end", segs: [w("get"), i("html")], legacy: ["get", "h", "t", "m", "l"] },
	{ name: "initialism in the middle", segs: [w("my"), i("api"), w("client")], legacy: ["my", "a", "p", "i", "client"] },
	{ name: "two-letter initialism", segs: [w("user"), i("id")], legacy: ["user", "i", "d"] },
	{ name: "leading initialism", segs: [i("io"), w("error")], legacy: ["i", "o", "error"] },
	{ name: "leading initialism, four letters", segs: [i("html"), w("parser")], legacy: ["h", "t", "m", "l", "parser"] },
	{ name: "single-letter word is a type variable", segs: [w("a")], legacy: ["a"] },
	{ name: "single-letter word after a word", segs: [w("max"), w("n")], legacy: ["max", "n"] },
	{ name: "digits-only segment is a word", segs: [w("2052")], legacy: ["2052"] },
	{ name: "initialism containing digits", segs: [i("fr2052a")] },
	{ name: "multi-segment name with an initialism", segs: [w("data"), i("id"), w("tables")], legacy: ["data", "i", "d", "tables"] },
	{ name: "windows reserved device name", segs: [w("aux")], legacy: ["aux"] },
	{ name: "windows reserved name as initialism", segs: [i("con")], legacy: ["c", "o", "n"] },
	{ name: "reserved word is safe when not the whole stem", segs: [w("nul"), w("pointer")], legacy: ["nul", "pointer"] },
	{ name: "reserved device name with digit", segs: [w("com1")], legacy: ["com1"] },
];

const LEGACY: readonly (readonly string[])[] = [
	["value", "in", "u", "s", "d"],
	["a"],
	["morphir", "s", "d", "k"],
	["point", "x", "y"],
	["max", "n"],
	["get", "h", "t", "m", "l"],
	["u", "s"],
	["f", "r", "2052", "a"],
];

const REJECT: readonly string[] = [
	"Usd", "value-in-(usd)", "user_id", "", "-user", "user-",
	"value-in--usd", "value-in-USD", "user--id", "morphir/SDK",
	"user---id", "--", "USD-usd", "MyName",
];

const PATHS: readonly NamePath[] = [
	[[w("morphir")], [i("sdk")]],
	[[i("us")], [i("fr2052a")], [w("data"), w("tables")]],
	[[w("my"), w("org")], [w("domain")], [w("users")]],
];

interface FqSpec {
	readonly pkg: NamePath;
	readonly mod: NamePath;
	readonly name: Name;
}

const FQNAMES: readonly FqSpec[] = [
	{ pkg: [[w("morphir")], [i("sdk")]], mod: [[w("list")]], name: [w("map")] },
	{ pkg: [[w("my"), w("org")]], mod: [[w("domain")]], name: [w("value"), w("in"), i("usd")] },
];

// ---------------------------------------------------------------- build

function build(): string {
	const failures: string[] = [];
	const reUp = new RegExp(P_UP);
	const reDb = new RegExp(P_DB);
	const reSt = new RegExp(P_ST);
	const stems = new Map<string, string>();

	const roundTripCases: RoundTripCase[] = ROUND_TRIP.map((c) => {
		const uppercase = encUpper(c.segs);
		const doubledHyphen = encDouble(c.segs);
		const escapedStem = escapeName(c.segs);
		const hasInit = c.segs.some((s) => s.kind === "initialism");

		if (!reUp.test(uppercase)) failures.push(`uppercase pattern: ${uppercase}`);
		if (!reDb.test(doubledHyphen)) failures.push(`doubledHyphen pattern: ${doubledHyphen}`);
		if (!reSt.test(escapedStem)) failures.push(`fileStem pattern: ${escapedStem}`);
		// Decision 0002 disjointness: a name carrying an initialism must not be
		// legal in the other style.
		if (hasInit && reDb.test(uppercase)) failures.push(`not disjoint: ${uppercase}`);
		if (hasInit && reUp.test(doubledHyphen)) failures.push(`not disjoint: ${doubledHyphen}`);

		const key = escapedStem.toLowerCase();
		const clash = stems.get(key);
		if (clash !== undefined) failures.push(`stem collision: ${escapedStem} (${c.name} vs ${clash})`);
		stems.set(key, c.name);

		if (c.legacy && JSON.stringify(legacyDecode(c.legacy)) !== JSON.stringify(c.segs)) {
			failures.push(`legacy decode mismatch for ${c.name}`);
		}

		return {
			name: c.name,
			segments: c.segs,
			canonical: { uppercase, doubledHyphen },
			escapedStem,
			rendered: render(c.segs),
			...(c.legacy ? { legacyArray: c.legacy } : {}),
		};
	});

	const doc: Corpus = {
		contractVersion: 1,
		description:
			"Conformance corpus for Morphir IR v4 name canonicalization. Accompanies kb decisions 0001-0003 and docs/design/proposals/ir-v4-name-encoding.md. Generated by tools/gen-naming-corpus.ts; per decision 0003 it is intended to become a build output of the Morphir model of the naming codec.",
		styles: ["uppercase", "doubledHyphen"],
		shippedStyle: "uppercase",
		notes: [
			'legacyDecodeCases apply the rule from decision 0001: a maximal run of two or more single-letter words collapses into one initialism, and a run of one stays a word. That run-of-one rule is what makes a single-letter type variable decode as the word "a" rather than as an initialism.',
			'The legacy array ["f","r","2052","a"] is inherently ambiguous, because the multi-character token 2052 breaks the letter run. The deterministic result recorded here renders identically to FR2052A in both PascalCase conventions but differs in snakeCase. Implementations must match the recorded value rather than guess.',
			"rejectCases record validity per style. An input legal under one style and not the other is the disjointness property that decision 0002 relies on for its union decoder.",
			"Path-length truncation from decision 0001 is not covered here, because it depends on a SHA-256 digest that the Morphir SDK cannot express. Those cases are host-verified.",
		],
		patterns: { name: { uppercase: P_UP, doubledHyphen: P_DB }, fileStem: P_ST },
		reservedDeviceStems: RESERVED,
		roundTripCases,
		legacyDecodeCases: LEGACY.map((legacyArray) => {
			const segments = legacyDecode(legacyArray);
			return {
				legacyArray,
				segments,
				canonical: {
					uppercase: encUpper(segments),
					doubledHyphen: encDouble(segments),
				},
			};
		}),
		rejectCases: REJECT.map((input) => ({
			input,
			validAs: { uppercase: reUp.test(input), doubledHyphen: reDb.test(input) },
		})),
		pathCases: PATHS.map((names) => ({
			canonical: {
				uppercase: pathStr(names, encUpper),
				doubledHyphen: pathStr(names, encDouble),
			},
			escapedPath: pathStr(names, escapeName),
		})),
		fqNameCases: FQNAMES.map((f) => ({
			canonical: {
				uppercase: `${pathStr(f.pkg, encUpper)}:${pathStr(f.mod, encUpper)}#${encUpper(f.name)}`,
				doubledHyphen: `${pathStr(f.pkg, encDouble)}:${pathStr(f.mod, encDouble)}#${encDouble(f.name)}`,
			},
			documentTreePath: `pkg/${pathStr(f.pkg, escapeName)}/${pathStr(f.mod, escapeName)}/${escapeName(f.name)}.value.json`,
		})),
	};

	if (failures.length > 0) {
		console.error("SELF-CHECK FAILED:");
		for (const failure of failures) console.error(`  ${failure}`);
		process.exit(1);
	}
	return `${JSON.stringify(doc, null, 2)}\n`;
}

// ---------------------------------------------------------------- main

const generated = build();

if (process.argv.includes("--check")) {
	const problems: string[] = [];
	const onDisk = existsSync(corpusPath)
		? readFileSync(corpusPath, "utf8")
		: null;
	if (onDisk !== generated) {
		problems.push(
			`${path.relative(repositoryRoot, corpusPath)} is stale; run "mise run fixtures:naming-corpus"`,
		);
	}
	if (existsSync(vendoredPath) && readFileSync(vendoredPath, "utf8") !== generated) {
		problems.push(
			`${path.relative(repositoryRoot, vendoredPath)} has drifted from the corpus`,
		);
	}
	if (problems.length > 0) {
		for (const problem of problems) console.error(`error: ${problem}`);
		process.exit(1);
	}
	console.log("naming corpus is up to date");
} else {
	writeFileSync(corpusPath, generated);
	// Keep the copy vendored into morphir-rust byte-identical, the same way
	// format-version-conformance.json is vendored.
	if (existsSync(path.dirname(vendoredPath))) {
		writeFileSync(vendoredPath, generated);
	}
	console.log(`wrote ${path.relative(repositoryRoot, corpusPath)}`);
}
