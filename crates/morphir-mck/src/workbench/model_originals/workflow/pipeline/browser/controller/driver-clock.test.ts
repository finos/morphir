import { expect, test } from "bun:test";
import { parseClock, acceptSample } from "./driver-clock";
test("same calibrated lower bound and original end, no new window", () => {
  const clock = parseClock("500", "538", "125", "3");
  expect(acceptSample(clock, 500n, 501n)).toBe(501n);
  expect(acceptSample(clock, 501n, 537n)).toBe(537n);
  expect(() => acceptSample(clock, 537n, 538n)).toThrow("original end elapsed");
});
test("decreasing and pre-calibration samples refuse", () => {
  const clock = parseClock("500", "538", "125", "3");
  expect(() => acceptSample(clock, 510n, 509n)).toThrow("clock decreased");
  expect(() => acceptSample(clock, 490n, 499n)).toThrow("outside calibrated range");
});
test("u64 libuv product horizon refuses before end comparison", () => {
  const clock = parseClock("1", "2", "125", "3");
  const limit = ((2n ** 64n - 1n) / 125n) * 125n / 3n;
  expect(() => acceptSample(clock, 1n, limit + 1n)).toThrow("outside calibrated range");
});
test("fixed metadata is exact canonical bounded integer data", () => {
  for (const value of ["", "01", "-1", "1.0", "18446744073709551616"]) {
    expect(() => parseClock(value, "538", "125", "3")).toThrow();
  }
  for (const ratio of ["0", "4294967296"]) expect(() => parseClock("500", "538", ratio, "3")).toThrow();
  expect(() => parseClock("539", "538", "125", "3")).toThrow();
});
