;; An extism-kernel-v1 guest that caches an IR value of 16 MiB + 1 byte under
;; "k", over the IR cache, and then answers
;; {"jsonrpc":"2.0","id":1,"result":"done"}.
;; Cases: sandbox/ir-cache-over-bytes
(module
  (import "extism:host/env" "alloc" (func $alloc (param i64) (result i64)))
  (import "extism:host/env" "store_u8" (func $store_u8 (param i64 i32)))
  (import "extism:host/env" "output_set" (func $output_set (param i64 i64)))
  (import "extism:host/user" "morphir_cache_ir" (func $cache_ir (param i64 i64)))
  (memory 1)
  (data (i32.const 0) "k")
  (data (i32.const 64) "{\22jsonrpc\22:\222.0\22,\22id\22:1,\22result\22:\22done\22}")
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
    (call $cache_ir (call $block (i32.const 0) (i32.const 1)) (call $alloc (i64.const 16777217)))
    (call $output_set (call $block (i32.const 64) (i32.const 40)) (i64.const 40))
    (i32.const 0)))
