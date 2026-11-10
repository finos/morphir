;; The extism-echo guest with one change: before it answers, it asks to grow
;; its memory by 4096 pages, which a 4096-page ceiling cannot grant to a
;; memory of 1 page. It answers with its input whether or not the growth was
;; granted. The memory declares a maximum of 65536 pages, above the ceiling.
;; Cases: bounds/grow-refused-then-respond
(module
  (import "extism:host/env" "input_length" (func $input_length (result i64)))
  (import "extism:host/env" "input_load_u8" (func $input_load_u8 (param i64) (result i32)))
  (import "extism:host/env" "alloc" (func $alloc (param i64) (result i64)))
  (import "extism:host/env" "store_u8" (func $store_u8 (param i64 i32)))
  (import "extism:host/env" "output_set" (func $output_set (param i64 i64)))
  (memory 1 65536)
  (func (export "handle") (result i32)
    (local $len i64) (local $block i64) (local $i i64)
    (drop (memory.grow (i32.const 4096)))
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
