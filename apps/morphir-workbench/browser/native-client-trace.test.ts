import { test } from "node:test";
import assert from "node:assert/strict";
import { core } from "./native-test-fixture.ts";
import { runNativeClientTrace } from "./native-client-trace.ts";
const v = "0.1.0-draft.1";
const descriptor = {
  profile: "morphir/workbench/native",
  contractVersion: v,
  sessionId: "session",
  operations: ["jobs"],
  offer: {
    profile: "morphir/workbench/jobs",
    contractVersion: v,
    hostId: "host",
    sessionId: "session",
    providerId: "scheme",
    operations: ["query", "cancel"],
  },
};
const reply = (operation: string) =>
  JSON.stringify({ ok: true, operation, value: descriptor });
test("lost submit reply retains uncertainty and refuses a second submission", async () => {
  const result = await runNativeClientTrace(
    {
      evaluation: {
        model: "{}",
        entry: "fixture:main#answer",
        inputs: { format: "json", source: "[]" },
      },
      inspectionSuccess: true,
      checkSource: reply("session.check"),
      invocations: [
        {
          id: "opening",
          operation: "session.open",
          source: reply("session.open"),
          held: false,
        },
        { id: "submit", operation: "job.submit", source: null, held: false },
      ],
      actions: [
        { op: "initialize", id: "init" },
        { op: "evaluate", id: "first" },
        { op: "evaluate", id: "retry" },
      ],
    },
    core(),
  );
  assert.equal(result.steps[1]!.jobs!.uncertainSubmission, true);
  assert.equal(result.steps[2]!.attempts[2]!.status, "rejected");
  assert.equal(
    result.requests.filter(
      (source) => JSON.parse(source).frame.operation === "job.submit",
    ).length,
    1,
  );
  assert.equal(result.steps[2]!.jobs!.job, null);
  assert.equal(result.consumed, 2);
  assert.equal(result.requests.length, 2);
});

test("a held query completion after disposal cannot publish progress", async () => {
  const identity = {
    hostId: "host",
    sessionId: "session",
    providerId: "scheme",
    jobId: "job-1",
    snapshotId: "snapshot-1",
  };
  const receipt = {
    contractVersion: v,
    identity,
    sequence: 0,
    state: "submitted",
    cancelRequested: false,
    outcomes: null,
  };
  const terminal = {
    ...receipt,
    sequence: 1,
    state: "terminal",
    outcomes: {
      contractVersion: "0.1.0-draft.5",
      calls: [
        {
          id: "workbench",
          outcome: { status: "returned", value: { type: "int", value: "42" } },
        },
      ],
      cleanup: null,
      extensions: null,
    },
  };
  const success = (operation: string, value: unknown) =>
    JSON.stringify({ ok: true, operation, value });
  const observed = await runNativeClientTrace(
    {
      evaluation: {
        model: "{}",
        entry: "fixture:main#answer",
        inputs: { format: "json", source: "[]" },
      },
      inspectionSuccess: true,
      checkSource: reply("session.check"),
      invocations: [
        {
          id: "opening",
          operation: "session.open",
          source: reply("session.open"),
          held: false,
        },
        {
          id: "submit",
          operation: "job.submit",
          source: success("job.submit", {
            identity,
            calls: ["workbench"],
            receipt,
          }),
          held: false,
        },
        {
          id: "query",
          operation: "job.query",
          source: success("job.query", terminal),
          held: true,
        },
        {
          id: "close",
          operation: "session.close",
          source: success("session.close", {}),
          held: false,
        },
      ],
      actions: [
        { op: "initialize", id: "init" },
        { op: "evaluate", id: "run" },
        { op: "poll" },
        { op: "dispose" },
        { op: "deliver", call: "query" },
      ],
    },
    core(),
  );
  assert.equal(
    observed.steps[4]!.progressCount,
    observed.steps[3]!.progressCount,
  );
  assert.equal(observed.steps[4]!.attempts[1]!.status, "rejected");
});

test("adapter framing rejects infrastructure faults without a domain observation", async () => {
  const { spawnSync } = await import("node:child_process");
  const { fileURLToPath } = await import("node:url");
  const command = fileURLToPath(
    new URL("../scripts/native-client-mck.ts", import.meta.url),
  );
  const env = {
    ...process.env,
    MORPHIR_WORKBENCH_CLIENT_CORE: fileURLToPath(
      new URL("../dist/job-core.js", import.meta.url),
    ),
    MORPHIR_WORKBENCH_CLIENT_BROWSER: "0",
  };
  const request = {
    id: 1,
    op: "capabilities",
    suite: "workbench",
    contractVersion: "0.1.0-draft.9",
  };
  const invoke = (input: string | Buffer) =>
    spawnSync(process.execPath, [command], {
      env,
      input,
      encoding: "utf8",
      timeout: 10000,
    });
  const accepted = invoke(
    JSON.stringify(request) +
      "\n" +
      JSON.stringify({ id: 2, op: "exit" }) +
      "\n",
  );
  assert.equal(accepted.status, 0, accepted.stderr);
  const caps = JSON.parse(accepted.stdout);
  assert.deepEqual(caps.operations, ["run-native-client"]);
  assert.deepEqual(caps.formats, ["json"]);
  for (const input of [
    JSON.stringify({ ...request, contractVersion: "0.1.0-draft.9+local" }) +
      "\n",
    JSON.stringify(request).replace('"id":1', '"id":1,"id":2') + "\n",
    JSON.stringify(request),
    Buffer.from([0xff, 10]),
    JSON.stringify({
      ...request,
      op: "run-native-client",
      format: "json",
      input: {},
    }) + "\n",
  ]) {
    const rejected = invoke(input);
    assert.equal(rejected.status, 1, rejected.stderr);
    assert.equal(rejected.stdout, "");
    assert.match(rejected.stderr, /infrastructure failure/);
  }
});
