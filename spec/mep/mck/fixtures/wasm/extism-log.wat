;; An extism-kernel-v1 guest that logs "kit-log-marker" with log_info and
;; answers {"jsonrpc":"2.0","id":1,"result":"logged"}.
;; Cases: sandbox/log-info
(module
  (import "extism:host/env" "alloc" (func $alloc (param i64) (result i64)))
  (import "extism:host/env" "store_u8" (func $store_u8 (param i64 i32)))
  (import "extism:host/env" "output_set" (func $output_set (param i64 i64)))
  (import "extism:host/env" "log_info" (func $log_info (param i64)))
  (memory 1)
  (data (i32.const 0) "kit-log-marker")
  (data (i32.const 64) "{\22jsonrpc\22:\222.0\22,\22id\22:1,\22result\22:\22logged\22}")
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
    (call $log_info (call $block (i32.const 0) (i32.const 14)))
    (call $output_set (call $block (i32.const 64) (i32.const 42)) (i64.const 42))
    (i32.const 0)))
