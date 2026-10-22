// Tests for the MEP contract regeneration script. Run with:
//   bun test tools/spec-mep.test.ts
//
// spec-mep.ts guards its CLI body behind `if (import.meta.main)`, so importing
// it here does not build or compile anything.
import { expect, test } from "bun:test";
import path from "node:path";
import { isolatedEnvironment } from "./spec-mep";

test("removes every MORPHIR_ variable, in any case, and keeps the rest", () => {
	const env = isolatedEnvironment(
		{ PATH: "/bin", MORPHIR_OUT_DIR: "/elsewhere", morphir_log_level: "trace", MORPHIRX: "kept" },
		"/tmp/isolated",
	);
	expect(env.PATH).toBe("/bin");
	expect(env.MORPHIRX).toBe("kept");
	expect(env.MORPHIR_OUT_DIR).toBeUndefined();
	expect(env.morphir_log_level).toBeUndefined();
});

test("points every home and config directory into the temporary root", () => {
	const root = path.join("/tmp", "isolated");
	const env = isolatedEnvironment({ HOME: "/Users/me", APPDATA: "C:\\Users\\me" }, root);
	expect(env).toMatchObject({
		HOME: path.join(root, "home"),
		USERPROFILE: path.join(root, "home"),
		XDG_CONFIG_HOME: path.join(root, "home", ".config"),
		APPDATA: path.join(root, "home", "AppData", "Roaming"),
		LOCALAPPDATA: path.join(root, "home", "AppData", "Local"),
		MORPHIR_HOME: path.join(root, "morphir-home"),
		MORPHIR_LOG_FILE: "false",
	});
});

test("drops a variable with no value", () => {
	expect(isolatedEnvironment({ EMPTY: undefined }, "/tmp/isolated")).not.toHaveProperty("EMPTY");
});
