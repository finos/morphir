// A bounded GitHub job summary for the authoritative MCK JSON report.
import { appendFileSync, readFileSync } from "node:fs";

type RecordEntry = {
	caseId: string;
	result: string;
	diff?: string;
	message?: string;
};
type Report = {
	execution: { session: { status: string; errors?: { phase: string; message: string }[] } };
	records: RecordEntry[];
};

function brief(value: string, limit: number): string {
	return value.length > limit ? `${value.slice(0, limit)}…` : value;
}

function quoted(value: string): string {
	return JSON.stringify(brief(value, 120));
}

export function formatMckSummary(binding: string, report: Report | null, artifact: string, runUrl: string): string {
	const lines = [`### MCK ${binding} conformance`, ""];
	if (report === null) {
		lines.push("No JSON report was produced. Check the run step for a build, adapter, or kit error.");
	} else {
		const counts = Object.fromEntries(["pass", "fail", "kit-error", "skipped"].map((result) => [result, report.records.filter((record) => record.result === result).length]));
		lines.push(`${counts.pass} pass, ${counts.fail} fail, ${counts["kit-error"]} kit-error, ${counts.skipped} skipped.`, "");
		const session = report.execution.session;
		if (session.status !== "finished") {
			lines.push(`Session ${session.status}.`);
			for (const error of (session.errors ?? []).slice(0, 3)) {
				lines.push(`- ${quoted(error.phase)}: ${quoted(error.message)}`);
			}
			lines.push("");
		}
		const failures = report.records.filter((record) => record.result === "fail" || record.result === "kit-error");
		if (failures.length > 0) {
			const caseIds = [...new Set(failures.map((record) => record.caseId))];
			lines.push(`Failed case IDs (first ${Math.min(caseIds.length, 20)} of ${caseIds.length}): ${caseIds.slice(0, 20).map(quoted).join(", ")}.`, "");
			lines.push(`First ${Math.min(failures.length, 5)} of ${failures.length} failing records:`, "");
			for (const record of failures.slice(0, 5)) {
				lines.push(`- ${quoted(record.caseId)}: ${record.result}${record.message ? ` — ${quoted(record.message)}` : ""}`);
				if (record.diff) {
					lines.push("", ...brief(record.diff, 600).split("\n").slice(0, 12).map((line) => `    ${line}`), "");
				}
			}
		}
	}
	lines.push(report === null
		? `Available run artifacts: [${artifact}](${runUrl}#artifacts).`
		: `Full JSON, HTML, and adapter transcript: [${artifact}](${runUrl}#artifacts).`, "");
	return lines.join("\n");
}

if (import.meta.main) {
	const [binding, reportPath, artifact] = process.argv.slice(2);
	if (!binding || !reportPath || !artifact) {
		console.error("usage: mck-ci-summary.ts <binding> <report.json> <artifact-name>");
		process.exit(2);
	}
	let report: Report | null = null;
	try {
		report = JSON.parse(readFileSync(reportPath, "utf8")) as Report;
	} catch (error) {
		if ((error as NodeJS.ErrnoException).code !== "ENOENT") throw error;
	}
	const runUrl = `https://github.com/${process.env.GITHUB_REPOSITORY ?? "finos/morphir"}/actions/runs/${process.env.GITHUB_RUN_ID ?? ""}`;
	const summary = formatMckSummary(binding, report, artifact, runUrl);
	if (process.env.GITHUB_STEP_SUMMARY) appendFileSync(process.env.GITHUB_STEP_SUMMARY, summary);
	else process.stdout.write(summary);
}
