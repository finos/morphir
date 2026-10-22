import { expect, test } from "bun:test";
import { builtExecutable } from "./cargo-artifacts.ts";

const artifact = (name: string, kind: string, executable: string | null) =>
	JSON.stringify({ reason: "compiler-artifact", target: { name, kind: [kind] }, executable });

test("takes the morphir binary from cargo's JSON messages", () => {
	const messages = [
		artifact("morphir_core", "lib", null),
		JSON.stringify({ reason: "compiler-message", message: {} }),
		artifact("morphir", "bin", "/repo/target/debug/morphir"),
		JSON.stringify({ reason: "build-finished", success: true }),
		"",
	].join("\n");
	expect(builtExecutable(messages)).toBe("/repo/target/debug/morphir");
});

test("ignores the morphir library and other binaries", () => {
	const messages = [artifact("morphir", "lib", null), artifact("other", "bin", "/repo/target/debug/other")].join("\n");
	expect(() => builtExecutable(messages)).toThrow("cargo reported no morphir binary");
});

test("ignores lines that are not JSON", () => {
	const messages = ["warning: something", artifact("morphir", "bin", "C:\\repo\\target\\debug\\morphir.exe")].join("\n");
	expect(builtExecutable(messages)).toBe("C:\\repo\\target\\debug\\morphir.exe");
});

test("ignores non-artifact JSON and malformed executable fields", () => {
	const messages = [
		"null", "false", "[]",
		JSON.stringify({ reason: "compiler-artifact", target: { name: "morphir", kind: "bin" }, executable: "/wrong-kind-shape" }),
		JSON.stringify({ reason: "compiler-artifact", target: { name: "morphir", kind: ["bin"] }, executable: 12 }),
		artifact("morphir", "bin", "/actual"),
	].join("\n");
	expect(builtExecutable(messages)).toBe("/actual");
});

test("selects the exact requested Cargo test target rather than a nearby binary", () => {
	const peer = "/custom target/debug/deps/mep_transport-123";
	const messages = [
		artifact("morphir", "bin", "/custom target/debug/morphir"),
		artifact("mep_transport", "bin", "/wrong-kind"),
		artifact("transport", "test", "/wrong-target"),
		artifact("mep_transport", "test", peer),
	].join("\n");
	expect(builtExecutable(messages, { name: "mep_transport", kind: "test" })).toBe(peer);
});

test("refuses distinct matching executables instead of selecting a stale candidate", () => {
	const selector = { name: "mep_transport", kind: "test" } as const;
	expect(() => builtExecutable([
		artifact("mep_transport", "test", "/first"),
		artifact("mep_transport", "test", "/second"),
	].join("\n"), selector)).toThrow("multiple mep_transport test executables");
	expect(builtExecutable([
		artifact("mep_transport", "test", "/same"),
		artifact("mep_transport", "test", "/same"),
	].join("\n"), selector)).toBe("/same");
});
