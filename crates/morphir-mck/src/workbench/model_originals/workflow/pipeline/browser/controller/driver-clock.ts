// Closed DATA arithmetic, shared by the actual fixed driver and pure controls.
export interface ClockExport {
  readonly calibrated: bigint;
  readonly end: bigint;
  readonly lastQualified: bigint;
}
const U64_MAX = 2n ** 64n - 1n;
function integer(text: string | undefined): bigint {
  if (text === undefined || !/^(0|[1-9][0-9]{0,19})$/.test(text)) throw new Error("clock integer shape");
  const value = BigInt(text);
  if (value > U64_MAX) throw new Error("clock integer range");
  return value;
}
export function parseClock(at: string | undefined, end: string | undefined, numer: string | undefined, denom: string | undefined): ClockExport {
  const calibrated = integer(at);
  const fixedEnd = integer(end);
  const numerator = integer(numer);
  const denominator = integer(denom);
  if (numerator === 0n || denominator === 0n || numerator > 4294967295n || denominator > 4294967295n) throw new Error("clock ratio");
  // Exact pinned libuv u64 multiplication horizon, not final quotient alone.
  const lastQualified = (U64_MAX / numerator) * numerator / denominator;
  if (calibrated >= fixedEnd || fixedEnd > lastQualified) throw new Error("clock export range");
  return { calibrated, end: fixedEnd, lastQualified };
}
export function acceptSample(clock: ClockExport, previous: bigint, current: bigint): bigint {
  if (current < clock.calibrated || current > clock.lastQualified) throw new Error("outside calibrated range");
  if (current < previous) throw new Error("clock decreased");
  if (current >= clock.end) throw new Error("original end elapsed");
  return current;
}
