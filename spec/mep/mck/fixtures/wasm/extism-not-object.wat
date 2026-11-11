;; An extism-kernel-v1 guest that answers every request with the two bytes
;; 42: UTF-8 text holding a JSON value that is not an object.
;; Cases: extism/response-not-object
(module
  (import "extism:host/env" "alloc" (func $alloc (param i64) (result i64)))
  (import "extism:host/env" "store_u8" (func $store_u8 (param i64 i32)))
  (import "extism:host/env" "output_set" (func $output_set (param i64 i64)))
  (func (export "handle") (result i32)
    (local $h i64)
    (local.set $h (call $alloc (i64.const 2)))
    (call $store_u8 (local.get $h) (i32.const 52))
    (call $store_u8 (i64.add (local.get $h) (i64.const 1)) (i32.const 50))
    (call $output_set (local.get $h) (i64.const 2))
    (i32.const 0)))
