import { expect, test } from "bun:test";
import { formatMckSummary } from "./mck-ci-summary";

test("summarizes outcomes and bounds failing diffs", () => {
	const report = {
		execution: { session: { status: "finished" } },
		records: [
			{ caseId: "values-0001", result: "pass" },
			{ caseId: "values-0002", result: "fail", diff: "-old\n+new\n".repeat(100) },
			{ caseId: "values-0003", result: "kit-error", message: "bad case" },
			{ caseId: "values-0004", result: "skipped" },
		],
	};
	const summary = formatMckSummary("Rust", report, "mck-report-morphir-rust", "https://github.com/finos/morphir/actions/runs/123");
	expect(summary).toContain("1 pass, 1 fail, 1 kit-error, 1 skipped");
	expect(summary).toContain("values-0002");
	expect(summary).toContain("values-0003");
	expect(summary).toContain("bad case");
	expect(summary).toContain("mck-report-morphir-rust");
	expect(summary.length).toBeLessThan(3000);
});

test("explains a missing report and includes a failed session", () => {
	expect(formatMckSummary("Rust", null, "artifact", "run")).toContain("No JSON report was produced");
	const summary = formatMckSummary("Rust", {
		execution: { session: { status: "failed", errors: [{ phase: "shutdown", message: "adapter exited" }] } },
		records: [],
	}, "artifact", "run");
	expect(summary).toContain("Session failed");
	expect(summary).toContain("adapter exited");
});
