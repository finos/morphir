// Tests for the WASM host kit check, and a self-test of the crafted fixtures.
// Run with:
//   bun test tools/check-wasm-host-kit.test.ts
//
// check-wasm-host-kit.ts guards its CLI body behind `if (import.meta.main)`,
// so importing it here does not run the check.
import { beforeAll, expect, test } from "bun:test";
import { readFileSync } from "node:fs";
import path from "node:path";
import { checkKit, classify, type Contract, documentProblems, type Kit, type KitInput, loadKit, readModule, withDigests } from "./check-wasm-host-kit";

const root = path.resolve(import.meta.dir, "..");
let input: KitInput;

beforeAll(async () => {
	input = await loadKit(root);
	const assemble = input.assemble;
	const built = new Map<string, Uint8Array>();
	input.assemble = (name, wat) => built.get(wat) ?? (built.set(wat, assemble(name, wat)), built.get(wat) as Uint8Array);
});

/** The failures of the committed kit after `change` edits a copy of it. */
function failuresAfter(change: (kit: Kit, contract: Contract) => void, read?: KitInput["read"]): string[] {
	const kit = structuredClone(input.kit);
	const contract = structuredClone(input.contract);
	change(kit, contract);
	return checkKit({ ...input, kit, contract, read: read ?? input.read });
}

const named = (failures: string[], text: string) => failures.some((failure) => failure.includes(text));
const caseNamed = (kit: Kit, id: string) => kit.cases.find((entry) => entry.caseId === id);

test("the committed kit passes", () => {
	expect(checkKit(input)).toEqual([]);
});

test("deleting any one case fails the check on coverage, not only on a stale fixture comment", () => {
	const redundant = input.kit.cases
		.filter((_, index) => failuresAfter((kit) => kit.cases.splice(index, 1)).filter((failure) => !failure.includes(";; Cases: line")).length === 0)
		.map((entry) => entry.caseId);
	expect(redundant).toEqual([]);
});

test("a .wasm that differs from a fresh assembly of its .wat fails", () => {
	const read: KitInput["read"] = (relative) => {
		const bytes = input.read(relative);
		if (!bytes || relative !== "fixtures/wasm/bytes-exit.wasm") return bytes;
		const changed = bytes.slice();
		changed[changed.length - 2] = 0x7f;
		return changed;
	};
	const failures = failuresAfter(() => {}, read);
	expect(named(failures, "bytes-exit.wasm differs from a fresh assembly")).toBe(true);
	expect(named(failures, "bytes-exit.wasm has sha256")).toBe(true);
});

test("a recorded sha256 that differs from the file fails", () => {
	expect(named(failuresAfter((kit) => void ((kit.modules["bytes-exit"] as { sha256: string }).sha256 = "00")), "the kit records 00")).toBe(true);
});

test("a missing module file fails", () => {
	const failures = failuresAfter((kit) => void ((kit.modules["bytes-exit"] as { wat: string }).wat = "fixtures/wasm/absent.wat"));
	expect(named(failures, "fixtures/wasm/absent.wat is missing")).toBe(true);
});

test("each kind of contract element with no case fails", () => {
	const failures = failuresAfter((_, contract) => {
		const bytes = contract.profiles["morphir-bytes-v1"];
		contract.refusals.push({ code: "extension.kit_probe" });
		contract.worker.refusals.push({ code: "extension.kit_worker_probe" });
		contract.faults.push({ kind: "kit-probe", hostCode: "extension.kit_probe" });
		bytes?.handleResults.push({ result: "-3" });
		bytes?.notifications.push({ id: "probe", rule: "A probe." });
		bytes?.memory?.push({ id: "probe", rule: "A probe." });
		contract.memory.push({ id: "probe", rule: "A probe." });
		contract.classification.rules.push({ id: "probe", rule: "A fourth rule." });
		contract.hostSession.rules.push({ id: "probe", rule: "A probe." });
		contract.worker.rules.push({ id: "probe", rule: "A probe." });
		(contract.policy.wasi as Record<string, unknown>).probe = 1;
	});
	for (const element of [
		"refusal:extension.kit_probe",
		"refusal:extension.kit_worker_probe",
		"fault:kit-probe",
		"hostOutcome:kit-probe",
		"handleResult:morphir-bytes-v1:-3",
		"notifications:morphir-bytes-v1:probe",
		"memory:morphir-bytes-v1:probe",
		"memory:probe",
		"classification:probe",
		"hostSession:probe",
		"worker:probe",
		"policy:wasi.probe",
	]) {
		expect(named(failures, `the contract element ${element} has no case`)).toBe(true);
	}
});

test("an element listed without a case must exist, have a reason and have no case", () => {
	const failures = failuresAfter((kit) => {
		kit.withoutCase.push({ element: "fault:trap", reason: "A probe." }, { element: "kit:probe", reason: "A probe." }, { element: "worker:defaults", reason: " " });
	});
	expect(named(failures, "withoutCase lists fault:trap, but case bounds/trap covers it")).toBe(true);
	expect(named(failures, "withoutCase lists kit:probe, which is not a contract element")).toBe(true);
	expect(named(failures, "withoutCase lists worker:defaults without a reason")).toBe(true);
	expect(named(failuresAfter((kit) => void kit.withoutCase.shift()), "the contract element classification:default has no case")).toBe(true);
});

test("a requirement or scenario that the specs lack fails", () => {
	const failures = failuresAfter((kit) => {
		kit.cases[0]?.tests.requirements.push("Hosts sing");
		kit.cases[0]?.tests.scenarios?.push("Sung request");
	});
	expect(named(failures, 'no requirement "Hosts sing"')).toBe(true);
	expect(named(failures, 'no scenario "Sung request"')).toBe(true);
});

test("a case's appliesTo follows from its module's profile", () => {
	const failures = failuresAfter((kit) => {
		const echo = caseNamed(kit, "bytes/echo");
		const extism = caseNamed(kit, "extism/echo");
		const unsupported = caseNamed(kit, "classification/bytes-profile-unsupported");
		if (echo) echo.appliesTo = "extism-kernel-v1";
		if (extism) extism.appliesTo = "morphir-bytes-v1";
		if (unsupported) unsupported.appliesTo = "morphir-bytes-v1";
	});
	expect(named(failures, "case bytes/echo: it applies to extism-kernel-v1, but its module is morphir-bytes-v1")).toBe(true);
	expect(named(failures, "case extism/echo: it applies to morphir-bytes-v1, but its module is extism-kernel-v1")).toBe(true);
	expect(named(failures, "case classification/bytes-profile-unsupported: it applies to morphir-bytes-v1, but its module is morphir-bytes-v1 and it selects by the host's profiles")).toBe(true);
});

test("a case without --abi fails unless it omits --abi on purpose", () => {
	const failures = failuresAfter((kit) => {
		const echo = caseNamed(kit, "extism/echo");
		if (echo) delete echo.declaredAbi;
		const missing = caseNamed(kit, "worker/missing-abi");
		if (missing) missing.declaredAbi = "extism-kernel-v1";
	});
	expect(named(failures, "case extism/echo: it declares no ABI, which the worker requires")).toBe(true);
	expect(named(failures, "case worker/missing-abi: it declares an ABI and omits --abi")).toBe(true);
});

test("a refusal expectation must rule out started", () => {
	const failures = failuresAfter((kit) => {
		const expectation = caseNamed(kit, "classification/memory64")?.runs[0]?.expect;
		if (expectation) expectation.noEvents = ["fault"];
	});
	expect(named(failures, "case classification/memory64 run 0: a refusal comes instead of started")).toBe(true);
});

test("the first import from a profile namespace decides the profile", () => {
	const imports = (...modules: string[]) => modules.map((module) => ({ module, name: "f", kind: "func" }));
	expect(classify(imports("env", "extism:host/env", "morphir_bytes_v1"), undefined, input.contract)).toBe("extism-kernel-v1");
	expect(classify(imports("morphir_bytes_v1", "wasi_snapshot_preview1"), undefined, input.contract)).toBe("morphir-bytes-v1");
	expect(classify(imports("env"), "morphir-bytes-v1", input.contract)).toBe("morphir-bytes-v1");
	expect(classify(imports("env"), undefined, input.contract)).toBe("extism-kernel-v1");
});

test("an accepted module whose import is outside the table, or has another signature, fails", () => {
	const failures = failuresAfter((_, contract) => {
		const bytes = contract.profiles["morphir-bytes-v1"];
		if (bytes) bytes.imports = bytes.imports.filter((entry) => entry.name !== "input_byte");
		const alloc = contract.profiles["extism-kernel-v1"]?.imports.find((entry) => entry.name === "alloc");
		if (alloc) alloc.params = ["i32"];
	});
	expect(named(failures, "morphir_bytes_v1.input_byte is not in the morphir-bytes-v1 import table")).toBe(true);
	expect(named(failures, "extism:host/env.alloc is (i64) -> i64, the table has (i32) -> i64")).toBe(true);
});

test("a claimed refusal that no expectation shows fails", () => {
	const failures = failuresAfter((kit) => caseNamed(kit, "bytes/echo")?.tests.contract?.push("refusal:extension.abi_mismatch"));
	expect(named(failures, "claims refusal:extension.abi_mismatch but no expectation shows that refusal")).toBe(true);
});

test("a deadline range that does not follow from the contract fails", () => {
	const failures = failuresAfter((kit) => {
		const late = caseNamed(kit, "bounds/spin-bytes")?.runs[0]?.alternatives?.[1]?.expect.withinSeconds;
		if (late) late.range = [10, 15];
	});
	expect(named(failures, "does not follow from the morphir-bytes-v1 deadline of 10 s")).toBe(true);
});

test("the document states every import, code, bound, policy value and worker argument of the JSON", () => {
	expect(documentProblems(input.contract, input.document)).toEqual([]);
	const without = (text: string) => input.document.split(text).join("");
	expect(documentProblems(input.contract, without("`extension.worker_runtime_mismatch`"))).toContain("the document does not mention the refusal code `extension.worker_runtime_mismatch`");
	expect(documentProblems(input.contract, without("5,000,000,000"))).toContain("the document does not state the 0.2.0-draft.1 instruction budget, 5000000000");
	expect(documentProblems(input.contract, input.document.replace("| `var.storeBytes` | `1048576` |", "| `var.storeBytes` | `1048575` |"))).toContain(
		"the document has no line with `var.storeBytes` and `1048576`",
	);
	expect(documentProblems(input.contract, input.document.replace("| `--call-ms` | No | 30000", "| `--call-ms` | No | 3000"))).toContain(
		"the document has no line with `--call-ms` and its default 30000, 10000",
	);
	expect(documentProblems(input.contract, without("| `input_byte` | `(i32) -> i32` |"))).toContain("the document has no line with `input_byte` and `(i32) -> i32`");
});

test("withDigests replaces only the named module's digest", () => {
	const text = '{"a": { "wat": "a.wat", "sha256": "11" }, "b": { "sha256": "22" }}';
	expect(withDigests(text, { a: "ff" })).toBe('{"a": { "wat": "a.wat", "sha256": "ff" }, "b": { "sha256": "22" }}');
});

test("frame limit cases stay far from the limit, so counting the header cannot change the result", () => {
	const header = (body: number) => `Content-Length: ${body}\r\n\r\n`.length;
	const limited = input.kit.cases.filter((entry) => entry.worker?.requestBytes !== undefined || entry.worker?.responseBytes !== undefined);
	expect(limited.map((entry) => entry.caseId).sort()).toEqual(["limits/request-over-limit", "limits/response-over-limit"]);
	for (const entry of limited) {
		const body = Buffer.byteLength(JSON.stringify(input.kit.frames[entry.runs[0]?.frames[0] ?? ""]));
		const limit = (entry.worker?.requestBytes ?? entry.worker?.responseBytes) as number;
		// The echo guest's response is the request, so one body serves both.
		expect(body).toBeGreaterThan(limit + header(body));
	}
});

// Fixture self-test. A test-only model of the two ABIs runs each runnable
// fixture with WebAssembly and checks that the module does what its case
// says. The model is not a host, and nothing here produces an expectation.

const wasm = (name: string) => new Uint8Array(readFileSync(path.join(root, "spec/mep/mck", input.kit.modules[name]?.wasm ?? "")));
const frame = (name: string) => new TextEncoder().encode(JSON.stringify(input.kit.frames[name]));
const text = (bytes: Uint8Array | undefined) => new TextDecoder("utf-8", { fatal: true }).decode(bytes);
const json = (bytes: Uint8Array | undefined) => JSON.parse(text(bytes)) as Record<string, unknown>;
const unexpected = (module: string, name: string) => () => {
	throw new Error(`the model does not provide ${module}.${name}`);
};

type Imports = ConstructorParameters<typeof WebAssembly.Instance>[1];

/** Imports for `module` from `provided`, with a throwing stub for the rest. */
function link(module: WebAssembly.Module, provided: Record<string, Record<string, unknown>>): Imports {
	const imports: Record<string, Record<string, unknown>> = {};
	for (const entry of WebAssembly.Module.imports(module)) {
		imports[entry.module] ??= {};
		(imports[entry.module] as Record<string, unknown>)[entry.name] = provided[entry.module]?.[entry.name] ?? unexpected(entry.module, entry.name);
	}
	return imports as Imports;
}

/** The module with its one memory capped at `pages` and exported as
 * "memory", so the model can apply a ceiling and read the size. */
function withCeiling(bytes: Uint8Array, pages: number): Uint8Array {
	const uleb = (value: number) => {
		const out: number[] = [];
		do out.push((value & 0x7f) | (value > 0x7f ? 0x80 : 0));
		while ((value >>>= 7) > 0);
		return out;
	};
	const min = readModule(bytes).memories[0]?.min ?? 0;
	const out = [...bytes.subarray(0, 8)];
	let at = 8;
	while (at < bytes.length) {
		const id = bytes[at++] as number;
		let size = 0;
		for (let shift = 0, next = 0x80; next & 0x80; shift += 7) size |= ((next = bytes[at++] as number) & 0x7f) << shift;
		let body = [...bytes.subarray(at, at + size)];
		if (id === 5) body = [1, 1, ...uleb(min), ...uleb(pages)];
		if (id === 7) body = [(body[0] as number) + 1, ...body.slice(1), 6, ...new TextEncoder().encode("memory"), 2, 0];
		out.push(id, ...uleb(body.length), ...body);
		at += size;
	}
	return new Uint8Array(out);
}

const pagesOf = (instance: WebAssembly.Instance) => (instance.exports.memory as WebAssembly.Memory).buffer.byteLength / 65536;

/** A module whose imports all throw: enough for a guest that never calls one. */
function plainGuest(bytes: Uint8Array) {
	const module = new WebAssembly.Module(bytes);
	const instance = new WebAssembly.Instance(module, link(module, {}));
	return { memoryPages: () => pagesOf(instance), call: () => (instance.exports.handle as () => number)() };
}

function bytesGuest(bytes: Uint8Array) {
	let message: Uint8Array = new Uint8Array();
	let output: number[] = [];
	const module = new WebAssembly.Module(bytes);
	const callbacks = { input_len: () => message.length, input_byte: (index: number) => message[index] ?? 0, output_byte: (value: number) => void output.push(value & 0xff) };
	const instance = new WebAssembly.Instance(module, link(module, { morphir_bytes_v1: callbacks }));
	return {
		memoryPages: () => pagesOf(instance),
		call(request: Uint8Array) {
			message = request;
			output = [];
			const result = (instance.exports.handle as () => number)();
			return { result, output: new Uint8Array(output) };
		},
	};
}

/** proc_exit in the model: it ends the guest's call. */
class ProcExit extends Error {
	constructor(readonly code: number) {
		super(`proc_exit(${code})`);
	}
}

/** One session of an Extism guest: a bump-allocating kernel shim whose first
 * handle is 77, and host and WASI functions after the contract's policy. */
function extismGuest(bytes: Uint8Array) {
	const policy = input.contract.policy as {
		var: { storeBytes: number };
		irCache: { bytes: number; entries: number };
		logging: { getLogLevel: number; levels: string[]; dropped: string[] };
		wasi: { fdAboveTwoErrno: number; unsupportedErrno: number };
	};
	const { fdAboveTwoErrno: BADF, unsupportedErrno: NOTCAPABLE } = policy.wasi;
	let kernel = new Uint8Array(1 << 16);
	let next = 65;
	const lengths = new Map<number, number>();
	const state = { input: new Uint8Array(), output: undefined as Uint8Array | undefined, error: undefined as string | undefined };
	const guestOutput: string[] = [];
	const vars = new Map<string, Uint8Array>();
	const cache = new Map<string, Uint8Array>();
	const alloc = (size: number) => {
		const handle = next + 12;
		if (handle + size > kernel.length) {
			const bigger = new Uint8Array(Math.max(handle + size, kernel.length * 2));
			bigger.set(kernel);
			kernel = bigger;
		}
		lengths.set(handle, size);
		next = handle + size;
		return handle;
	};
	const block = (handle: bigint) => kernel.slice(Number(handle), Number(handle) + (lengths.get(Number(handle)) ?? 0));
	const put = (data: Uint8Array) => {
		const handle = alloc(data.length);
		kernel.set(data, handle);
		return BigInt(handle);
	};
	const store = (into: Map<string, Uint8Array>, limit: number, entries: number, key: bigint, value: bigint) => {
		if (value === 0n) return void into.delete(text(block(key)));
		into.set(text(block(key)), block(value));
		const total = [...into].reduce((sum, [name, data]) => sum + name.length + data.length, 0);
		if (total > limit || into.size > entries) throw new Error("the store is over its limit");
	};
	const log = (level: string) => (handle: bigint) => {
		if (!policy.logging.dropped.includes(level)) guestOutput.push(text(block(handle)));
	};
	const env = {
		alloc: (size: bigint) => BigInt(alloc(Number(size))),
		length: (handle: bigint) => BigInt(lengths.get(Number(handle)) ?? 0),
		load_u8: (offset: bigint) => kernel[Number(offset)] ?? 0,
		input_length: () => BigInt(state.input.length),
		input_load_u8: (offset: bigint) => state.input[Number(offset)] ?? 0,
		store_u8: (offset: bigint, value: number) => void (kernel[Number(offset)] = value),
		output_set: (handle: bigint, size: bigint) => void (state.output = kernel.slice(Number(handle), Number(handle + size))),
		error_set: (handle: bigint) => void (state.error = text(block(handle))),
		config_get: () => 0n,
		var_get: (key: bigint) => (vars.has(text(block(key))) ? put(vars.get(text(block(key))) as Uint8Array) : 0n),
		var_set: (key: bigint, value: bigint) => store(vars, policy.var.storeBytes, Infinity, key, value),
		get_log_level: () => policy.logging.getLogLevel,
		...Object.fromEntries(policy.logging.levels.map((level) => [`log_${level}`, log(level)])),
		http_request: (request: bigint) => {
			const { method, url } = JSON.parse(text(block(request))) as { method: string; url: string };
			guestOutput.push(`${method} ${url}`);
			throw new Error("http_request stops the call");
		},
		http_status_code: () => 0,
		http_headers: () => 0n,
	};
	const user = {
		morphir_get_workspace_info: () => put(new TextEncoder().encode('{"root":"/model-workspace","output_dir":""}')),
		morphir_cache_ir: (key: bigint, value: bigint) => store(cache, policy.irCache.bytes, policy.irCache.entries, key, value),
		morphir_get_cached_ir: (key: bigint) => put(cache.get(text(block(key))) ?? new TextEncoder().encode("null")),
		morphir_log: (level: bigint, message: bigint) => void guestOutput.push(`${text(block(level))}: ${text(block(message))}`),
	};
	const view = () => new DataView((instance.exports.memory as WebAssembly.Memory).buffer);
	const zero = (...pointers: number[]) => (pointers.forEach((pointer) => view().setUint32(pointer, 0, true)), 0);
	const wasi = {
		fd_write: (fd: number, iovs: number, count: number, written: number) => {
			if (fd > 2) return BADF;
			if (fd === 0) return NOTCAPABLE;
			let total = 0;
			for (let index = 0; index < count; index++) {
				const [pointer, size] = [view().getUint32(iovs + 8 * index, true), view().getUint32(iovs + 8 * index + 4, true)];
				guestOutput.push(text(new Uint8Array(view().buffer, pointer, size)));
				total += size;
			}
			view().setUint32(written, total, true);
			return 0;
		},
		path_open: (fd: number) => (fd > 2 ? BADF : NOTCAPABLE),
		fd_prestat_get: (fd: number) => (fd > 2 ? BADF : NOTCAPABLE),
		fd_read: (fd: number, _iovs: number, _count: number, read: number) => (fd > 2 ? BADF : fd === 0 ? zero(read) : NOTCAPABLE),
		poll_oneoff: () => NOTCAPABLE,
		proc_exit: (code: number) => {
			throw new ProcExit(code);
		},
		args_sizes_get: (count: number, size: number) => zero(count, size),
		environ_sizes_get: (count: number, size: number) => zero(count, size),
		clock_time_get: (_id: number, _precision: bigint, time: number) => (view().setBigUint64(time, BigInt(Date.now()) * 1_000_000n, true), 0),
		random_get: (buffer: number, size: number) => (crypto.getRandomValues(new Uint8Array(view().buffer, buffer, size)), 0),
	};
	const module = new WebAssembly.Module(bytes);
	const instance = new WebAssembly.Instance(module, link(module, { "extism:host/env": env, "extism:host/user": user, wasi_snapshot_preview1: wasi }));
	return {
		guestOutput,
		cacheEntries: () => cache.size,
		memoryPages: () => pagesOf(instance),
		call(request: Uint8Array) {
			Object.assign(state, { input: request, output: undefined, error: undefined });
			let result: number;
			try {
				result = (instance.exports.handle as () => number)();
			} catch (error) {
				if (!(error instanceof ProcExit) || error.code !== 0) throw error;
				result = 0;
			}
			return { result, output: state.output, error: state.error };
		},
	};
}

/** The notification rule of the Extism profile, as a model: the frames in
 * order, a notification delivered only after the initialize result
 * advertised acceptance, and output for one is a failure. The responses. */
function extismSession(guest: ReturnType<typeof extismGuest>, frames: string[]) {
	let accepts = false;
	const responses: Record<string, unknown>[] = [];
	for (const name of frames) {
		const message = input.kit.frames[name] as Record<string, unknown>;
		if ("id" in message) {
			const response = json(guest.call(frame(name)).output);
			if (message.method === "morphir.initialize") {
				accepts = (response as { result?: { capabilities?: { notifications?: { accept?: unknown } } } }).result?.capabilities?.notifications?.accept === true;
			}
			responses.push(response);
		} else if (accepts) {
			const { result, output } = guest.call(frame(name));
			if (result !== 0 || output !== undefined) throw new Error(`the guest answered the notification ${name}`);
		}
		if (message.method === "morphir.exit") break;
	}
	return responses;
}

/** Whether handle is still running after `ms`, in a worker thread. */
function spins(bytes: Uint8Array, ms: number): Promise<boolean> {
	const source = `onmessage = ({ data }) => {
		const module = new WebAssembly.Module(data);
		const imports = {};
		for (const entry of WebAssembly.Module.imports(module)) (imports[entry.module] ??= {})[entry.name] = () => { throw new Error("no import"); };
		new WebAssembly.Instance(module, imports).exports.handle();
		postMessage("returned");
	};`;
	const worker = new Worker(URL.createObjectURL(new Blob([source], { type: "application/javascript" })));
	return new Promise((resolve) => {
		const timer = setTimeout(() => (worker.terminate(), resolve(true)), ms);
		worker.onmessage = () => (clearTimeout(timer), worker.terminate(), resolve(false));
		worker.onerror = () => (clearTimeout(timer), worker.terminate(), resolve(false));
		worker.postMessage(bytes);
	});
}

test("byte guests: echo, exit for any message, notification, failure and non-UTF-8 codes", () => {
	const echo = bytesGuest(wasm("bytes-echo"));
	const request = frame("initialize");
	expect(echo.call(request)).toEqual({ result: request.length, output: request });
	expect(echo.call(frame("initialized")).result).toBe(-2);
	expect(echo.call(frame("exit")).result).toBe(0);
	expect(bytesGuest(wasm("bytes-exit")).call(request)).toEqual({ result: 0, output: new Uint8Array() });
	expect(bytesGuest(wasm("bytes-minus-two")).call(frame("initialize-id-4")).result).toBe(-2);
	expect(bytesGuest(wasm("bytes-minus-one")).call(request).result).toBe(-1);
	const garbled = bytesGuest(wasm("bytes-not-utf8")).call(request);
	expect(garbled).toEqual({ result: 2, output: new Uint8Array([0xff, 0xfe]) });
	expect(() => text(garbled.output)).toThrow();
	expect(bytesGuest(wasm("no-imports")).call(frame("exit")).result).toBe(0);
});

test("memory guests stop at the ceiling the model gives them", () => {
	const trapping = plainGuest(withCeiling(wasm("extism-grow-then-trap"), 8));
	expect(() => trapping.call()).toThrow(WebAssembly.RuntimeError);
	expect(trapping.memoryPages()).toBe(8);
	const recovering = extismGuest(withCeiling(wasm("extism-grow-then-respond"), 8));
	expect(recovering.call(frame("initialize")).output).toEqual(frame("initialize"));
	expect(recovering.memoryPages()).toBe(1);
	const bytes = bytesGuest(withCeiling(wasm("bytes-grow-then-respond"), 8));
	expect(bytes.call(frame("initialize")).output).toEqual(frame("initialize"));
	expect(bytes.memoryPages()).toBe(8);
	const large = plainGuest(withCeiling(wasm("extism-grow-below-ceiling"), 4096));
	expect(() => large.call()).toThrow(WebAssembly.RuntimeError);
	expect(large.memoryPages()).toBe(1600);
	expect(() => extismGuest(wasm("extism-trap")).call(frame("initialize"))).toThrow(WebAssembly.RuntimeError);
	expect(readModule(wasm("initial-memory-4097")).memories[0]?.min).toBe(4097);
});

test("spinning guests do not return", async () => {
	expect(await spins(wasm("bytes-spin"), 300)).toBe(true);
	expect(await spins(wasm("extism-spin"), 300)).toBe(true);
	expect(await spins(wasm("bytes-exit"), 1000)).toBe(false);
});

test("Extism guests: echo, error, non-zero, no output, not an object and the full import surface", () => {
	const request = frame("initialize");
	expect(extismGuest(wasm("extism-echo")).call(request)).toEqual({ result: 0, output: request, error: undefined });
	expect(extismGuest(wasm("extism-full-surface")).call(request).output).toEqual(request);
	expect(extismGuest(wasm("extism-error")).call(request)).toEqual({ result: 1, output: undefined, error: "boom" });
	const nonzero = extismGuest(wasm("extism-nonzero")).call(request);
	expect([nonzero.result, json(nonzero.output), nonzero.error]).toEqual([1, { jsonrpc: "2.0", id: 1, result: "done" }, undefined]);
	expect(extismGuest(wasm("extism-no-output")).call(request)).toEqual({ result: 0, output: undefined, error: undefined });
	expect(JSON.parse(text(extismGuest(wasm("extism-not-object")).call(request).output))).toBe(42);
});

test("Extism notifications: delivered only after the guest advertises, and an answer to one is a failure", () => {
	const frames = ["initialize", "initialized", "shutdown", "exit"];
	const advertised = { jsonrpc: "2.0", id: 1, result: { protocolVersion: "0.2.0-draft.1", capabilities: { notifications: { accept: true } } } };
	expect(extismSession(extismGuest(wasm("extism-count-calls")), frames)).toEqual([
		{ jsonrpc: "2.0", id: 1, result: 1 },
		{ jsonrpc: "2.0", id: 2, result: 2 },
	]);
	expect(extismSession(extismGuest(wasm("extism-notify-accept")), frames)).toEqual([advertised, { jsonrpc: "2.0", id: 2, result: 3 }]);
	const answering = extismGuest(wasm("extism-notify-answer"));
	expect(() => extismSession(answering, ["initialize", "initialized", "exit"])).toThrow("answered the notification initialized");
	expect(json(extismGuest(wasm("extism-notify-answer")).call(frame("initialize")).output)).toEqual(advertised);
});

test("sandbox guests report what the policy gives them", () => {
	const request = frame("initialize");
	const result = (name: string) => json(extismGuest(wasm(name)).call(request).output).result;
	const http = extismGuest(wasm("extism-http"));
	expect(() => http.call(request)).toThrow("http_request stops the call");
	expect(http.guestOutput).toEqual(["GET https://example.org/"]);
	expect(
		["extism-http-status", "extism-path-open", "extism-wasi-unsupported", "extism-wasi-empty", "extism-clock-random", "extism-config", "extism-proc-exit"].map(result),
	).toEqual(["tt", "t", "tt", "tttt", "ttt", "t", "exited"]);
	const printer = extismGuest(wasm("extism-fd-write"));
	expect(json(printer.call(request).output).result).toBe("printed");
	expect(printer.guestOutput).toEqual(["kit-stdout-marker\n", "kit-stderr-marker\n"]);
	const logger = extismGuest(wasm("extism-log"));
	expect(json(logger.call(request).output).result).toBe("level-2");
	expect(logger.guestOutput).toEqual(["kit-info--marker", "kit-warn--marker", "kit-error-marker", "trace: kit-morph-marker"]);
	expect(result("extism-workspace-info")).toEqual({ root: "/model-workspace", output_dir: "" });
});

test("session stores round trip in one session, start empty in the next, and refuse writes over the limit", () => {
	for (const [name, second] of [["extism-var-round-trip", "from-var"], ["extism-ir-cache-round-trip", "from-cache"]] as const) {
		const session = extismGuest(wasm(name));
		expect(json(session.call(frame("initialize")).output)).toEqual({ jsonrpc: "2.0", id: 1, result: "stored" });
		expect(json(session.call(frame("shutdown")).output)).toEqual({ jsonrpc: "2.0", id: 2, result: second });
		expect(json(extismGuest(wasm(name)).call(frame("initialize")).output).result).toBe("stored");
	}
	const deleted = extismGuest(wasm("extism-var-round-trip"));
	deleted.call(frame("initialize"));
	deleted.call(frame("shutdown"));
	expect(json(deleted.call(frame("shutdown")).output).result).toBe("stored");
	expect(() => extismGuest(wasm("extism-var-over-limit")).call(frame("initialize"))).toThrow("over its limit");
	expect(() => extismGuest(wasm("extism-ir-cache-over-bytes")).call(frame("initialize"))).toThrow("over its limit");
	const entries = extismGuest(wasm("extism-ir-cache-over-entries"));
	expect(() => entries.call(frame("initialize"))).toThrow("over its limit");
	expect(entries.cacheEntries()).toBe(1025);
});
