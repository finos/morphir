;; An extism-kernel-v1 guest that writes "kit-stdout-marker\n" to WASI fd 1
;; and "kit-stderr-marker\n" to fd 2, then answers
;; {"jsonrpc":"2.0","id":1,"result":"printed"}.
;; Cases: sandbox/fd-write
(module
  (import "extism:host/env" "alloc" (func $alloc (param i64) (result i64)))
  (import "extism:host/env" "store_u8" (func $store_u8 (param i64 i32)))
  (import "extism:host/env" "output_set" (func $output_set (param i64 i64)))
  (import "wasi_snapshot_preview1" "fd_write" (func $fd_write (param i32 i32 i32 i32) (result i32)))
  (memory (export "memory") 1)
  ;; Two iovecs: 18 bytes at 32, and 18 bytes at 64.
  (data (i32.const 0) "\20\00\00\00\12\00\00\00\40\00\00\00\12\00\00\00")
  (data (i32.const 32) "kit-stdout-marker\0a")
  (data (i32.const 64) "kit-stderr-marker\0a")
  (data (i32.const 1024) "{\22jsonrpc\22:\222.0\22,\22id\22:1,\22result\22:\22printed\22}")
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
    (drop (call $fd_write (i32.const 1) (i32.const 0) (i32.const 1) (i32.const 16)))
    (drop (call $fd_write (i32.const 2) (i32.const 8) (i32.const 1) (i32.const 16)))
    (call $output_set (call $block (i32.const 1024) (i32.const 43)) (i64.const 43))
    (i32.const 0)))
