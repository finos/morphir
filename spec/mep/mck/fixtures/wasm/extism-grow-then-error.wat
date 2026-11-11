;; An extism-kernel-v1 guest that grows its memory until the host refuses a
;; growth of one page, then reports the failure itself: it sets the Extism
;; error "boom" and returns 1. It asks for 2048 pages at a time and halves
;; the request after each refusal, so it stops exactly at the ceiling. The
;; guest ended the call, so the fault is a failure and not a memory limit.
;; Cases: bounds/error-at-ceiling
(module
  (import "extism:host/env" "alloc" (func $alloc (param i64) (result i64)))
  (import "extism:host/env" "store_u8" (func $store_u8 (param i64 i32)))
  (import "extism:host/env" "error_set" (func $error_set (param i64)))
  (memory 1)
  (data (i32.const 0) "boom")
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
    (local $step i32)
    (local.set $step (i32.const 2048))
    (loop $grow
      (if (i32.eq (memory.grow (local.get $step)) (i32.const -1))
        (then (local.set $step (i32.shr_u (local.get $step) (i32.const 1)))))
      (br_if $grow (local.get $step)))
    (call $error_set (call $block (i32.const 0) (i32.const 4)))
    (i32.const 1)))
