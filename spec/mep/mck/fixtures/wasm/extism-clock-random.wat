;; An extism-kernel-v1 guest that reads the WASI realtime clock and 16 random
;; bytes. It answers {"jsonrpc":"2.0","id":1,"result":"ttt"} when, in order:
;; clock_time_get returned errno 0; the time is not 0; random_get returned
;; errno 0. A failed check leaves its "f".
;; Cases: sandbox/clock-random
(module
  (import "extism:host/env" "alloc" (func $alloc (param i64) (result i64)))
  (import "extism:host/env" "store_u8" (func $store_u8 (param i64 i32)))
  (import "extism:host/env" "output_set" (func $output_set (param i64 i64)))
  (import "wasi_snapshot_preview1" "clock_time_get" (func $clock_time_get (param i32 i64 i32) (result i32)))
  (import "wasi_snapshot_preview1" "random_get" (func $random_get (param i32 i32) (result i32)))
  (memory (export "memory") 1)
  ;; 39 bytes; the flags are at 1058 to 1060.
  (data (i32.const 1024) "{\22jsonrpc\22:\222.0\22,\22id\22:1,\22result\22:\22fff\22}")
  ;; Copies $len bytes of guest memory at $ptr into a new kernel block.
  (func $block (param $ptr i32) (param $len i32) (result i64)
    (local $h i64) (local $i i32)
    (local.set $h (call $alloc (i64.extend_i32_u (local.get $len))))
    (block $copied
      (loop $copy
        (br_if $copied (i32.ge_u (local.get $i) (local.get $len)))
        (call $store_u8
          (i64.add (local.get $h) (i64.extend_i32_u (local.get $i)))
          (i32.load8_u (i32.add (local.get $ptr) (local.get $i))))
        (local.set $i (i32.add (local.get $i) (i32.const 1)))
        (br $copy)))
    (local.get $h))
  (func (export "handle") (result i32)
    (if (i32.eqz (call $clock_time_get (i32.const 0) (i64.const 1) (i32.const 0)))
      (then (i32.store8 (i32.const 1058) (i32.const 116))))
    (if (i64.ne (i64.load (i32.const 0)) (i64.const 0))
      (then (i32.store8 (i32.const 1059) (i32.const 116))))
    (if (i32.eqz (call $random_get (i32.const 16) (i32.const 16)))
      (then (i32.store8 (i32.const 1060) (i32.const 116))))
    (call $output_set (call $block (i32.const 1024) (i32.const 39)) (i64.const 39))
    (i32.const 0)))
