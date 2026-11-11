;; An extism-kernel-v1 guest that counts its handle calls in a global and
;; answers call n with {"jsonrpc":"2.0","id":n,"result":n}. A host that
;; delivered a notification would make the count, and so the id, too high.
;; Cases: extism/notifications-not-delivered
(module
  (import "extism:host/env" "alloc" (func $alloc (param i64) (result i64)))
  (import "extism:host/env" "store_u8" (func $store_u8 (param i64 i32)))
  (import "extism:host/env" "output_set" (func $output_set (param i64 i64)))
  (memory 1)
  (global $calls (mut i32) (i32.const 0))
  ;; 35 bytes; the digits are at offsets 22 and 33.
  (data (i32.const 0) "{\22jsonrpc\22:\222.0\22,\22id\22:0,\22result\22:0}")
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
    (global.set $calls (i32.add (global.get $calls) (i32.const 1)))
    (i32.store8 (i32.const 22) (i32.add (i32.const 48) (global.get $calls)))
    (i32.store8 (i32.const 33) (i32.add (i32.const 48) (global.get $calls)))
    (call $output_set (call $block (i32.const 0) (i32.const 35)) (i64.const 35))
    (i32.const 0)))
