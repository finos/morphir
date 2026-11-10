;; An extism-kernel-v1 guest that copies the Extism input into a new kernel
;; block and sets it as the output, so each request is answered with itself.
;; Cases: extism/echo, classification/declared-abi-mismatch, worker/other-build-identity, limits/response-over-limit
(module
  (import "extism:host/env" "input_length" (func $input_length (result i64)))
  (import "extism:host/env" "input_load_u8" (func $input_load_u8 (param i64) (result i32)))
  (import "extism:host/env" "alloc" (func $alloc (param i64) (result i64)))
  (import "extism:host/env" "store_u8" (func $store_u8 (param i64 i32)))
  (import "extism:host/env" "output_set" (func $output_set (param i64 i64)))
  (func (export "handle") (result i32)
    (local $len i64) (local $block i64) (local $i i64)
    (local.set $len (call $input_length))
    (local.set $block (call $alloc (local.get $len)))
    (block $copied
      (loop $copy
        (br_if $copied (i64.ge_u (local.get $i) (local.get $len)))
        (call $store_u8
          (i64.add (local.get $block) (local.get $i))
          (call $input_load_u8 (local.get $i)))
        (local.set $i (i64.add (local.get $i) (i64.const 1)))
        (br $copy)))
    (call $output_set (local.get $block) (local.get $len))
    (i32.const 0)))
