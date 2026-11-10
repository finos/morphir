// Tests for the WASM host kit check, and a self-test of the crafted fixtures.
// Run with:
//   bun test tools/check-wasm-host-kit.test.ts
//
// check-wasm-host-kit.ts guards its CLI body behind `if (import.meta.main)`,
// so importing it here does not run the check.
import { beforeAll, expect, test } from "bun:test";
import { readFileSync } from "node:fs";
import path from "node:path";
import { checkKit, type Contract, type Kit, type KitInput, loadKit, readModule, withDigests } from "./check-wasm-host-kit";

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
		contract.refusals.push({ code: "extension.kit_probe" });
		contract.faults.push({ kind: "kit-probe" });
		contract.profiles["morphir-bytes-v1"]?.handleResults.push({ result: "-3" });
		contract.classification.order.push("A fourth rule.");
	});
	for (const element of ["refusal:extension.kit_probe", "fault:kit-probe", "handleResult:morphir-bytes-v1:-3", "classification:3"]) {
		expect(named(failures, `the contract element ${element} has no case`)).toBe(true);
	}
});

test("a requirement or scenario that the profile spec lacks fails", () => {
	const failures = failuresAfter((kit) => {
		kit.cases[0]?.tests.requirements.push("Hosts sing");
		kit.cases[0]?.tests.scenarios?.push("Sung request");
	});
	expect(named(failures, 'no requirement "Hosts sing"')).toBe(true);
	expect(named(failures, 'no scenario "Sung request"')).toBe(true);
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
	const failures = failuresAfter((kit) => kit.cases.find((entry) => entry.caseId === "bytes/echo")?.tests.contract?.push("refusal:extension.request_limit"));
	expect(named(failures, "claims refusal:extension.request_limit but no expectation shows that refusal")).toBe(true);
});

test("a deadline range that does not follow from the contract fails", () => {
	const failures = failuresAfter((kit) => {
		const late = kit.cases.find((entry) => entry.caseId === "bounds/spin-bytes")?.runs[0]?.alternatives?.[1]?.expect.withinSeconds;
		if (late) late.range = [10, 15];
	});
	expect(named(failures, "does not follow from the morphir-bytes-v1 deadline of 10 s")).toBe(true);
});

test("withDigests replaces only the named module's digest", () => {
	const text = '{"a": { "wat": "a.wat", "sha256": "11" }, "b": { "sha256": "22" }}';
	expect(withDigests(text, { a: "ff" })).toBe('{"a": { "wat": "a.wat", "sha256": "ff" }, "b": { "sha256": "22" }}');
});

test("the request-limit message names the limit and the byte length of the frame", () => {
	const entry = input.kit.cases.find((candidate) => candidate.caseId === "limits/request-over-limit");
	const refused = entry?.runs[0]?.expect?.events?.find((matcher) => matcher.event === "refused");
	const size = Buffer.byteLength(JSON.stringify(input.kit.frames.initialize));
	expect(refused?.messageIncludes).toEqual([String(entry?.worker?.requestBytes), String(size)]);
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

function bytesGuest(bytes: Uint8Array) {
	let message: Uint8Array = new Uint8Array();
	let output: number[] = [];
	const module = new WebAssembly.Module(bytes);
	const callbacks = { input_len: () => message.length, input_byte: (index: number) => message[index] ?? 0, output_byte: (value: number) => void output.push(value & 0xff) };
	const instance = new WebAssembly.Instance(module, link(module, { morphir_bytes_v1: callbacks }));
	return {
		memoryPages: () => (instance.exports.memory as WebAssembly.Memory).buffer.byteLength / 65536,
		call(request: Uint8Array) {
			message = request;
			output = [];
			const result = (instance.exports.handle as () => number)();
			return { result, output: new Uint8Array(output) };
		},
	};
}

/** One session of an Extism guest: a bump-allocating kernel shim whose first
 * handle is 77, and host and WASI functions after the contract's policy. */
function extismGuest(bytes: Uint8Array) {
	const policy = input.contract.policy as { varStoreBytes: number; irCacheBytes: number; irCacheEntries: number };
	let kernel = new Uint8Array(1 << 16);
	let next = 65;
	const lengths = new Map<number, number>();
	const state = { input: new Uint8Array(), output: undefined as Uint8Array | undefined, error: undefined as string | undefined };
	const guestOutput: string[] = [];
	const http: string[] = [];
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
		into.set(text(block(key)), block(value));
		const total = [...into].reduce((sum, [name, data]) => sum + name.length + data.length, 0);
		if (total > limit || into.size > entries) throw new Error("the store is over its limit");
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
		var_set: (key: bigint, value: bigint) => store(vars, policy.varStoreBytes, Infinity, key, value),
		log_info: (handle: bigint) => void guestOutput.push(text(block(handle))),
		http_request: (request: bigint) => (http.push(text(block(request))), 0n),
	};
	const user = {
		morphir_get_workspace_info: () => put(new TextEncoder().encode('{"root":"/model-workspace","output_dir":""}')),
		morphir_cache_ir: (key: bigint, value: bigint) => store(cache, policy.irCacheBytes, policy.irCacheEntries, key, value),
		morphir_get_cached_ir: (key: bigint) => (cache.has(text(block(key))) ? put(cache.get(text(block(key))) as Uint8Array) : 0n),
	};
	const view = () => new DataView((instance.exports.memory as WebAssembly.Memory).buffer);
	const zero = (...pointers: number[]) => (pointers.forEach((pointer) => view().setUint32(pointer, 0, true)), 0);
	const wasi = {
		fd_write: (fd: number, iovs: number, count: number, written: number) => {
			if (fd !== 1 && fd !== 2) return 8;
			let total = 0;
			for (let index = 0; index < count; index++) {
				const [pointer, size] = [view().getUint32(iovs + 8 * index, true), view().getUint32(iovs + 8 * index + 4, true)];
				guestOutput.push(text(new Uint8Array(view().buffer, pointer, size)));
				total += size;
			}
			view().setUint32(written, total, true);
			return 0;
		},
		path_open: () => 8,
		fd_prestat_get: () => 8,
		args_sizes_get: (count: number, size: number) => zero(count, size),
		environ_sizes_get: (count: number, size: number) => zero(count, size),
		fd_read: (_fd: number, _iovs: number, _count: number, read: number) => zero(read),
		clock_time_get: (_id: number, _precision: bigint, time: number) => (view().setBigUint64(time, BigInt(Date.now()) * 1_000_000n, true), 0),
		random_get: (buffer: number, size: number) => (crypto.getRandomValues(new Uint8Array(view().buffer, buffer, size)), 0),
	};
	const module = new WebAssembly.Module(bytes);
	const instance = new WebAssembly.Instance(module, link(module, { "extism:host/env": env, "extism:host/user": user, wasi_snapshot_preview1: wasi }));
	return {
		guestOutput,
		http,
		cacheEntries: () => cache.size,
		call(request: Uint8Array) {
			Object.assign(state, { input: request, output: undefined, error: undefined });
			const result = (instance.exports.handle as () => number)();
			return { result, output: state.output, error: state.error };
		},
	};
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

test("byte guests: echo, exit, notification, failure and non-UTF-8 codes", () => {
	const echo = bytesGuest(wasm("bytes-echo"));
	const request = frame("initialize");
	expect(echo.call(request)).toEqual({ result: request.length, output: request });
	expect(echo.call(frame("initialized")).result).toBe(-2);
	expect(echo.call(frame("exit")).result).toBe(0);
	expect(bytesGuest(wasm("bytes-exit")).call(request).result).toBe(0);
	expect(bytesGuest(wasm("bytes-minus-two")).call(frame("initialize-id-4")).result).toBe(-2);
	expect(bytesGuest(wasm("bytes-minus-one")).call(request).result).toBe(-1);
	const garbled = bytesGuest(wasm("bytes-not-utf8")).call(request);
	expect(garbled).toEqual({ result: 2, output: new Uint8Array([0xff, 0xfe]) });
	expect(() => text(garbled.output)).toThrow();
	const fixed = bytesGuest(wasm("bytes-fixed-response")).call(request);
	expect([fixed.result, fixed.output.length, json(fixed.output)]).toEqual([40, 40, { jsonrpc: "2.0", id: 1, result: "done" }]);
	expect(bytesGuest(wasm("no-imports")).call(frame("exit")).result).toBe(0);
});

test("memory guests stop at the ceiling the model gives them", () => {
	const trapping = bytesGuest(withCeiling(wasm("bytes-grow-then-trap"), 8));
	expect(() => trapping.call(frame("initialize"))).toThrow(WebAssembly.RuntimeError);
	expect(trapping.memoryPages()).toBe(8);
	const recovering = bytesGuest(withCeiling(wasm("bytes-grow-then-respond"), 8));
	expect(recovering.call(frame("initialize")).output).toEqual(frame("initialize"));
	expect(recovering.memoryPages()).toBe(8);
	const large = bytesGuest(withCeiling(wasm("bytes-grow-below-ceiling"), 4096));
	expect(() => large.call(frame("initialize"))).toThrow(WebAssembly.RuntimeError);
	expect(large.memoryPages()).toBe(1600);
	expect(() => extismGuest(wasm("extism-trap")).call(frame("initialize"))).toThrow(WebAssembly.RuntimeError);
});

test("spinning guests do not return", async () => {
	expect(await spins(wasm("bytes-spin"), 300)).toBe(true);
	expect(await spins(wasm("extism-spin"), 300)).toBe(true);
	expect(await spins(wasm("bytes-exit"), 1000)).toBe(false);
});

test("Extism guests: echo, error, call count and the full import surface", () => {
	const request = frame("initialize");
	expect(extismGuest(wasm("extism-echo")).call(request)).toEqual({ result: 0, output: request, error: undefined });
	expect(extismGuest(wasm("extism-full-surface")).call(request).output).toEqual(request);
	expect(extismGuest(wasm("extism-error")).call(request)).toEqual({ result: 1, output: undefined, error: "boom" });
	const counter = extismGuest(wasm("extism-count-calls"));
	expect(json(counter.call(request).output)).toEqual({ jsonrpc: "2.0", id: 1, result: 1 });
	expect(json(counter.call(frame("shutdown")).output)).toEqual({ jsonrpc: "2.0", id: 2, result: 2 });
});

test("sandbox guests report what the policy gives them", () => {
	const request = frame("initialize");
	const result = (name: string) => json(extismGuest(wasm(name)).call(request).output).result;
	const http = extismGuest(wasm("extism-http"));
	expect(json(http.call(request).output).result).toBe("done");
	expect(JSON.parse(http.http[0] ?? "{}")).toEqual({ url: "https://example.org/", method: "GET" });
	expect([result("extism-path-open"), result("extism-wasi-empty"), result("extism-clock-random"), result("extism-config")]).toEqual(["t", "tttt", "ttt", "t"]);
	const printer = extismGuest(wasm("extism-fd-write"));
	expect(json(printer.call(request).output).result).toBe("printed");
	expect(printer.guestOutput).toEqual(["kit-stdout-marker\n", "kit-stderr-marker\n"]);
	const logger = extismGuest(wasm("extism-log"));
	expect(json(logger.call(request).output).result).toBe("logged");
	expect(logger.guestOutput).toEqual(["kit-log-marker"]);
	expect(result("extism-workspace-info")).toEqual({ root: "/model-workspace", output_dir: "" });
});

test("session stores round trip in one session, start empty in the next, and refuse writes over the limit", () => {
	for (const [name, second] of [["extism-var-round-trip", "from-var"], ["extism-ir-cache-round-trip", "from-cache"]] as const) {
		const session = extismGuest(wasm(name));
		expect(json(session.call(frame("initialize")).output)).toEqual({ jsonrpc: "2.0", id: 1, result: "stored" });
		expect(json(session.call(frame("shutdown")).output)).toEqual({ jsonrpc: "2.0", id: 2, result: second });
		expect(json(extismGuest(wasm(name)).call(frame("initialize")).output).result).toBe("stored");
	}
	expect(() => extismGuest(wasm("extism-var-over-limit")).call(frame("initialize"))).toThrow("over its limit");
	expect(() => extismGuest(wasm("extism-ir-cache-over-bytes")).call(frame("initialize"))).toThrow("over its limit");
	const entries = extismGuest(wasm("extism-ir-cache-over-entries"));
	expect(() => entries.call(frame("initialize"))).toThrow("over its limit");
	expect(entries.cacheEntries()).toBe(1025);
});
