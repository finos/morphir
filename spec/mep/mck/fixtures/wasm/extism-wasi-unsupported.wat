;; An extism-kernel-v1 guest that calls two WASI functions the sandbox does
;; not support: poll_oneoff for one clock subscription, which would otherwise
;; block, and path_open on fd 0. It answers
;; {"jsonrpc":"2.0","id":1,"result":"tt"} when each returns errno 76
;; (notcapable). A failed check leaves its "f".
;; Cases: sandbox/wasi-unsupported
(module
  (import "extism:host/env" "alloc" (func $alloc (param i64) (result i64)))
  (import "extism:host/env" "store_u8" (func $store_u8 (param i64 i32)))
  (import "extism:host/env" "output_set" (func $output_set (param i64 i64)))
  (import "wasi_snapshot_preview1" "poll_oneoff"
    (func $poll_oneoff (param i32 i32 i32 i32) (result i32)))
  (import "wasi_snapshot_preview1" "path_open"
    (func $path_open (param i32 i32 i32 i32 i32 i64 i64 i32 i32) (result i32)))
  (memory (export "memory") 1)
  ;; A clock subscription at 0: userdata 0, tag 0 (clock), monotonic clock,
  ;; a timeout of 10 s, relative.
  (data (i32.const 16) "\01\00\00\00")
  (data (i32.const 24) "\00\e4\0b\54\02\00\00\00")
  (data (i32.const 512) "/etc/passwd")
  ;; 38 bytes; the flags are at 1058 and 1059.
  (data (i32.const 1024) "{\22jsonrpc\22:\222.0\22,\22id\22:1,\22result\22:\22ff\22}")
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
    (if (i32.eq (call $poll_oneoff (i32.const 0) (i32.const 128) (i32.const 1) (i32.const 192)) (i32.const 76))
      (then (i32.store8 (i32.const 1058) (i32.const 116))))
    (if (i32.eq
          (call $path_open (i32.const 0) (i32.const 0) (i32.const 512) (i32.const 11) (i32.const 0)
            (i64.const 0) (i64.const 0) (i32.const 0) (i32.const 256))
          (i32.const 76))
      (then (i32.store8 (i32.const 1059) (i32.const 116))))
    (call $output_set (call $block (i32.const 1024) (i32.const 38)) (i64.const 38))
    (i32.const 0)))
