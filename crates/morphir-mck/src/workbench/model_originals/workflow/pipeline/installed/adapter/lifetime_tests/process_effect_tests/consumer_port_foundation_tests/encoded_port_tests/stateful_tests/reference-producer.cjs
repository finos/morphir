// TEST reference transport only. No consumer wrapper or business facts.
// Intentionally synchronous: ACK progress must not need this Node event loop.
"use strict";
const fs = require("node:fs");
const version = "0.1.0-draft.1";
const decimal = (name) => {
  const text = process.env[name];
  if (typeof text !== "string" || !/^(0|[1-9][0-9]*)$/.test(text)) {
    throw new Error(`invalid exact integer ${name}`);
  }
  return BigInt(text);
};
if (process.env.MORPHIR_PRIVATE_CONSUMER_VERSION !== version ||
    process.env.MORPHIR_PRIVATE_CONSUMER_CLOCK_VERSION !== version ||
    process.env.MORPHIR_PRIVATE_CONSUMER_CLOCK_DOMAIN !== "darwin-mach-continuous-nanoseconds") {
  throw new Error("unsupported explicit clock metadata");
}
const calibrated = decimal("MORPHIR_PRIVATE_CONSUMER_CLOCK_AT_NS");
const end = decimal("MORPHIR_PRIVATE_CONSUMER_END_NS");
if (decimal("MORPHIR_PRIVATE_CONSUMER_TIMEBASE_NUMER") !== 125n ||
    decimal("MORPHIR_PRIVATE_CONSUMER_TIMEBASE_DENOM") !== 3n ||
    calibrated >= end || end > 6148914691236517166n) {
  throw new Error("outside selected candidate clock range");
}
const descriptor = (key) => {
  const raw = decimal(key);
  if (raw < 3n || raw > 2147483647n) throw new Error("descriptor range");
  // OS descriptors are i32. No clock or wide counter passes through Number.
  return Number(raw);
};
const outer = descriptor("MORPHIR_PRIVATE_CONSUMER_OUTER_FD");
const helper = descriptor("MORPHIR_PRIVATE_CONSUMER_HELPER_FD");
if (outer === helper) throw new Error("roles require distinct actual endpoints");
let poisoned = false;
let previousClock = calibrated;
const check = () => {
  if (poisoned) throw new Error("prior delivery fault");
  const now = process.hrtime.bigint();
  if (now < previousClock || now >= end || now > 6148914691236517166n) {
    throw new Error("fixed end expired, clock decreased or outside selected range");
  }
  previousClock = now;
};
const transient = (error) => error.code === "EAGAIN" || error.code === "EWOULDBLOCK" || error.code === "EINTR";
const transfer = (fd, bytes, write) => {
  let cursor = 0;
  while (cursor < bytes.length) {
    check();
    try {
      const count = write
        ? fs.writeSync(fd, bytes, cursor, bytes.length - cursor)
        : fs.readSync(fd, bytes, cursor, bytes.length - cursor, null);
      if (count === 0) throw new Error("actual endpoint EOF or zero write");
      cursor += count;
    } catch (error) {
      if (!transient(error)) throw error;
    }
  }
};
const emit = (fd, payload, sequence) => {
  check();
  const body = Buffer.from(payload, "utf8");
  if (body.length > 256) throw new Error("reference control frame bound");
  const header = Buffer.alloc(4);
  header.writeUInt32BE(body.length);
  transfer(fd, header, true);
  transfer(fd, body, true);
  const ack = Buffer.from(`{"kind":"retained","version":"${version}","sequence":${sequence}}`, "utf8");
  const gotHeader = Buffer.alloc(4);
  transfer(fd, gotHeader, false);
  if (gotHeader.readUInt32BE() !== ack.length) throw new Error("ACK exact length");
  const got = Buffer.alloc(ack.length);
  transfer(fd, got, false);
  if (!got.equals(ack)) throw new Error("ACK exact closed literal");
};
let eventLoopRan = false;
setTimeout(() => { eventLoopRan = true; }, 0);
try {
  emit(outer, `{"kind":"open","version":"${version}","sequence":0}`, 0);
  if (eventLoopRan) throw new Error("event loop ran during synchronous ACK wait");
  emit(helper, `{"kind":"open","version":"${version}","sequence":0}`, 0);
  emit(helper, `{"kind":"close","version":"${version}","sequence":1,"attemptedHooks":0,"startedFactFrames":0,"retainedBusinessFacts":0,"helper":{"kind":"not-applicable"}}`, 1);
  emit(outer, `{"kind":"close","version":"${version}","sequence":1,"attemptedHooks":0,"startedFactFrames":0,"retainedBusinessFacts":0,"helper":{"kind":"in-process"}}`, 1);
  fs.writeSync(1, "reference-control-close-retained\n");
} catch (error) {
  poisoned = true;
  // No FaultedClose or later protocol I/O. Diagnostics are ordinary stderr.
  fs.writeSync(2, "reference-delivery-fault\n");
  process.exitCode = 2;
} finally {
  for (const fd of [helper, outer]) {
    try { fs.closeSync(fd); } catch (_) { process.exitCode = 2; }
  }
}
