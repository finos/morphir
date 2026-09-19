// A recording proxy for the Morphir Compatibility Kit's JSON-lines protocol.
//
//   bun run tools/record-mck-transcript.ts <transcript.ndjson> <adapter> [args...]
//
// The driver spawns this in place of the adapter; it spawns the real adapter
// and copies every line through untouched, writing each one to the transcript
// as {"dir":"request"|"response","message":<the line>}. The message is the
// adapter's own bytes, not a re-serialization, so a transcript records exactly
// what crossed the pipe and a replay can hold a second runner to it byte for
// byte (spec/mck/migration.md, "Parity method").
//
// It is development and CI tooling: the shipped CLI never depends on it.
import { spawn } from "node:child_process";
import { createWriteStream } from "node:fs";
import { createInterface } from "node:readline";

const [transcript, command, ...args] = process.argv.slice(2);
if (transcript === undefined || command === undefined) {
	console.error("usage: record-mck-transcript <transcript.ndjson> <adapter> [args...]");
	process.exit(2);
}

const out = createWriteStream(transcript, { encoding: "utf8" });
const child = spawn(command, args, { stdio: ["pipe", "pipe", "inherit"], windowsHide: true });

// A transcript pairs each response with the request above it, so it can only
// describe a session that waits for an answer before asking again. The
// protocol is that session; a driver that pipelined would be recorded wrong.
let outstanding = false;

function die(message: string): never {
	console.error(`error: ${message}`);
	child.kill();
	process.exit(1);
}

/** Records one line, refusing anything a transcript cannot represent. */
function record(direction: "request" | "response", line: string): void {
	let message: unknown;
	try {
		message = JSON.parse(line);
	} catch {
		die(`${direction} is not JSON: ${line}`);
	}
	if (message === null || typeof message !== "object" || Array.isArray(message)) {
		die(`${direction} is not a JSON object: ${line}`);
	}
	if (direction === "request" && outstanding) {
		die("the driver sent a request before its last was answered; a transcript cannot pair them");
	}
	outstanding = direction === "request";
	out.write(`{"dir":"${direction}","message":${line}}\n`);
}

createInterface({ input: process.stdin })
	.on("line", (line) => {
		record("request", line);
		child.stdin.write(`${line}\n`);
	})
	.on("close", () => child.stdin.end());

createInterface({ input: child.stdout })
	.on("line", (line) => {
		record("response", line);
		process.stdout.write(`${line}\n`);
	});

child.on("exit", (code) => out.end(() => process.exit(code ?? 1)));
