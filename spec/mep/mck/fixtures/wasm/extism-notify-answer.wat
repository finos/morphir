;; An extism-kernel-v1 guest that advertises, in its answer to its first
;; call, that it accepts notifications: capabilities.notificationDelivery
;; with the value "call". Every later call, a notification
;; included, gives the output {"jsonrpc":"2.0","id":1,"result":"answer"}.
;; Cases: extism/notification-answered
(module
  (import "extism:host/env" "alloc" (func $alloc (param i64) (result i64)))
  (import "extism:host/env" "store_u8" (func $store_u8 (param i64 i32)))
  (import "extism:host/env" "output_set" (func $output_set (param i64 i64)))
  (memory 1)
  (global $calls (mut i32) (i32.const 0))
  ;; 116 bytes.
  (data (i32.const 16) "{\22jsonrpc\22:\222.0\22,\22id\22:1,\22result\22:{\22protocolVersion\22:\220.2.0-draft.1\22,\22capabilities\22:{\22notificationDelivery\22:\22call\22}}}")
  ;; 42 bytes.
  (data (i32.const 256) "{\22jsonrpc\22:\222.0\22,\22id\22:1,\22result\22:\22answer\22}")
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
    (if (i32.eq (global.get $calls) (i32.const 1))
      (then
        (call $output_set (call $block (i32.const 16) (i32.const 116)) (i64.const 116))
        (return (i32.const 0))))
    (call $output_set (call $block (i32.const 256) (i32.const 42)) (i64.const 42))
    (i32.const 0)))
