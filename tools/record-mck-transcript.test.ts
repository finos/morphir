import { expect, test } from "bun:test";
import { mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

const proxy = path.join(path.dirname(fileURLToPath(import.meta.url)), "record-mck-transcript.ts");

/** An adapter that answers each request with its id and echoes its argv. */
function fakeAdapter(): string {
	const directory = mkdtempSync(path.join(tmpdir(), "mck-record-"));
	const file = path.join(directory, "adapter.ts");
	writeFileSync(file, `
		import { createInterface } from "node:readline";
		const args = process.argv.slice(2);
		createInterface({ input: process.stdin }).on("line", (line) => {
			const { id } = JSON.parse(line);
			process.stdout.write(JSON.stringify({ id, ok: true, args }) + "\\n");
		});
	`);
	return file;
}

function run(args: string[], input: string) {
	const transcript = path.join(mkdtempSync(path.join(tmpdir(), "mck-record-")), "t.ndjson");
	const result = Bun.spawnSync(["bun", proxy, transcript, "bun", ...args], {
		stdin: Buffer.from(input),
		stdout: "pipe",
		stderr: "pipe",
	});
	return { result, transcript };
}

/** Drives the proxy the way the driver does: one request, then its answer. */
async function exchange(args: string[], requests: string[]) {
	const transcript = path.join(mkdtempSync(path.join(tmpdir(), "mck-record-")), "t.ndjson");
	const child = Bun.spawn(["bun", proxy, transcript, "bun", ...args], {
		stdin: "pipe",
		stdout: "pipe",
		stderr: "pipe",
	});
	const answers: string[] = [];
	const lines = child.stdout.getReader();
	let buffered = "";
	for (const request of requests) {
		child.stdin.write(`${request}\n`);
		await child.stdin.flush();
		while (!buffered.includes("\n")) {
			const { value, done } = await lines.read();
			if (done) break;
			buffered += new TextDecoder().decode(value);
		}
		const [answer, ...rest] = buffered.split("\n");
		answers.push(answer as string);
		buffered = rest.join("\n");
	}
	child.stdin.end();
	await child.exited;
	return { answers, transcript, exitCode: child.exitCode };
}

test("every line is recorded in order and passed through untouched", async () => {
	const requests = [`{"id":1,"op":"capabilities"}`, `{"id":2,"op":"decode","input":"é"}`];
	const { answers, transcript, exitCode } = await exchange([fakeAdapter()], requests);

	expect(exitCode).toBe(0);
	expect(answers).toEqual([
		`{"id":1,"ok":true,"args":[]}`,
		`{"id":2,"ok":true,"args":[]}`,
	]);
	expect(readFileSync(transcript, "utf8")).toBe([
		`{"dir":"request","message":${requests[0]}}`,
		`{"dir":"response","message":{"id":1,"ok":true,"args":[]}}`,
		`{"dir":"request","message":${requests[1]}}`,
		`{"dir":"response","message":{"id":2,"ok":true,"args":[]}}`,
		"",
	].join("\n"));
});

test("a request sent before the last was answered is refused, not recorded wrong", () => {
	const { result } = run([fakeAdapter()], `{"id":1}\n{"id":2}\n`);
	expect(result.exitCode).toBe(1);
	expect(result.stderr.toString()).toContain("cannot pair them");
});

test("the adapter keeps its own arguments", () => {
	const { transcript } = run([fakeAdapter(), "--suite", "package"], `{"id":1}\n`);
	expect(readFileSync(transcript, "utf8")).toContain(`"args":["--suite","package"]`);
});

test("an adapter's exit code is the proxy's", () => {
	const directory = mkdtempSync(path.join(tmpdir(), "mck-record-"));
	const file = path.join(directory, "adapter.ts");
	writeFileSync(file, "process.exit(7);");
	expect(run([file], "").result.exitCode).toBe(7);
});

test("naming no adapter is a usage error", () => {
	const result = Bun.spawnSync(["bun", proxy, "only-a-transcript.ndjson"], { stderr: "pipe" });
	expect(result.exitCode).toBe(2);
	expect(result.stderr.toString()).toContain("usage:");
});
