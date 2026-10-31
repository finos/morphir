///|
test "IR cache: the key bytes count toward the byte limit" {
  let cache = IrCache::new(bytes=10, entries=4)
  cache.store("abcd", b"123") // 7 bytes
  assert_eq(cache.get("abcd"), Some(b"123"))
  // 7 bytes, and 4 more for a key of 2 and a value of 2: over 10.
  assert_true((Ok(cache.store("ef", b"45")) catch { e => Err(e) }) is Err(_))
  assert_eq(cache.get("ef"), None)
  // Replacing a value frees the old one: 4 + 6 = 10.
  cache.store("abcd", b"123456")
  assert_eq(cache.bytes, 10)
}

///|
test "IR cache: the number of entries is capped" {
  let cache = IrCache::new(bytes=1000000, entries=1024)
  for index in 0..<1024 {
    cache.store("k\{index}", b"v")
  }
  guard (Ok(cache.store("one more", b"v")) catch { e => Err(e) }) is Err(error) else {
    fail("an entry over the cap was stored")
  }
  assert_true(@debug.to_string(error).contains("1024"))
  // An existing key may still change.
  cache.store("k0", b"w")
  assert_eq(cache.get("k0"), Some(b"w"))
  assert_eq(cache.values.length(), 1024)
}

///|
test "IR cache: the session limits are 16 MiB with the keys, and 1,024 entries" {
  assert_eq(IR_CACHE_BYTES, 16777216)
  assert_eq(IR_CACHE_ENTRIES, 1024)
}

///|
test "random_get: a count above the memory ceiling is refused before the source runs" {
  let calls = Ref(0)
  let source = (count : Int32) => {
    calls.val += 1
    Bytes::make(count, b'\x07')
  }
  let ceiling = @wasm.MemoryCeiling::of_pages(1)
  assert_eq(random_bytes(65537, ceiling, source), b"")
  assert_eq(random_bytes(-1, ceiling, source), b"")
  assert_eq(calls.val, 0)
  assert_eq(random_bytes(4, ceiling, source), b"\x07\x07\x07\x07")
  assert_eq(calls.val, 1)
}

///|
test "monotonic clock: a clock that moves backwards gives no smaller time" {
  let readings = [1000UL, 1500UL, 900UL, 2000UL]
  let index = Ref(0)
  let clock = MonotonicClock::new(() => {
    let value = readings[index.val]
    index.val += 1
    value
  })
  assert_eq(clock.elapsed_ms(), 500UL)
  // The source went back to 900: the clock stays at 500.
  assert_eq(clock.elapsed_ms(), 500UL)
  assert_eq(clock.elapsed_ms(), 1000UL)
}
