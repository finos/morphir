;; An extism-kernel-v1 guest that caches 1,025 IR entries, one over the IR
;; cache's entry limit, each a 1-byte value "0" under a distinct 3-byte key
;; of letters a to p, and then answers {"jsonrpc":"2.0","id":1,"result":"done"}.
;; Cases: sandbox/ir-cache-over-entries
(module
  (import "extism:host/env" "alloc" (func $alloc (param i64) (result i64)))
  (import "extism:host/env" "store_u8" (func $store_u8 (param i64 i32)))
  (import "extism:host/env" "output_set" (func $output_set (param i64 i64)))
  (import "extism:host/user" "morphir_cache_ir" (func $cache_ir (param i64 i64)))
  (memory 1)
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
    (local $n i32) (local $key i64) (local $value i64)
    (block $stored
      (loop $store
        (br_if $stored (i32.ge_u (local.get $n) (i32.const 1025)))
        (local.set $key (call $alloc (i64.const 3)))
        (call $store_u8 (local.get $key)
          (i32.add (i32.const 97) (i32.and (local.get $n) (i32.const 15))))
        (call $store_u8 (i64.add (local.get $key) (i64.const 1))
          (i32.add (i32.const 97) (i32.and (i32.shr_u (local.get $n) (i32.const 4)) (i32.const 15))))
        (call $store_u8 (i64.add (local.get $key) (i64.const 2))
          (i32.add (i32.const 97) (i32.and (i32.shr_u (local.get $n) (i32.const 8)) (i32.const 15))))
        (local.set $value (call $alloc (i64.const 1)))
        (call $store_u8 (local.get $value) (i32.const 48))
        (call $cache_ir (local.get $key) (local.get $value))
        (local.set $n (i32.add (local.get $n) (i32.const 1)))
        (br $store)))
    (call $output_set (call $block (i32.const 64) (i32.const 40)) (i64.const 40))
    (i32.const 0)))
