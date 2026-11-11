;; An extism-kernel-v1 guest that accepts notifications. It answers its first
;; request, morphir.initialize, with a result that gives
;; capabilities.notificationDelivery the value "call". It counts every
;; handle call. A message without "id" is a notification: it gives no output.
;; Its second request is answered with {"jsonrpc":"2.0","id":2,"result":n},
;; where n is the number of handle calls so far, so a delivered notification
;; makes n one higher.
;; Cases: extism/notifications-accepted
(module
  (import "extism:host/env" "input_length" (func $input_length (result i64)))
  (import "extism:host/env" "input_load_u8" (func $input_load_u8 (param i64) (result i32)))
  (import "extism:host/env" "alloc" (func $alloc (param i64) (result i64)))
  (import "extism:host/env" "store_u8" (func $store_u8 (param i64 i32)))
  (import "extism:host/env" "output_set" (func $output_set (param i64 i64)))
  (memory 1)
  (global $calls (mut i32) (i32.const 0))
  (global $requests (mut i32) (i32.const 0))
  (data (i32.const 0) "\22id\22")
  ;; 116 bytes.
  (data (i32.const 16) "{\22jsonrpc\22:\222.0\22,\22id\22:1,\22result\22:{\22protocolVersion\22:\220.2.0-draft.1\22,\22capabilities\22:{\22notificationDelivery\22:\22call\22}}}")
  ;; 35 bytes; the count is at 256 + 33.
  (data (i32.const 256) "{\22jsonrpc\22:\222.0\22,\22id\22:2,\22result\22:0}")
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
  ;; 1 when the input contains the four bytes "id", with the quotes.
  (func $is_request (result i32)
    (local $len i64) (local $i i64) (local $j i32)
    (local.set $len (call $input_length))
    (loop $start
      (if (i64.gt_u (i64.add (local.get $i) (i64.const 4)) (local.get $len))
        (then (return (i32.const 0))))
      (local.set $j (i32.const 0))
      (block $differs
        (loop $compare
          (if (i32.eq (local.get $j) (i32.const 4)) (then (return (i32.const 1))))
          (br_if $differs
            (i32.ne
              (call $input_load_u8 (i64.add (local.get $i) (i64.extend_i32_u (local.get $j))))
              (i32.load8_u (local.get $j))))
          (local.set $j (i32.add (local.get $j) (i32.const 1)))
          (br $compare)))
      (local.set $i (i64.add (local.get $i) (i64.const 1)))
      (br $start))
    (i32.const 0))
  (func (export "handle") (result i32)
    (global.set $calls (i32.add (global.get $calls) (i32.const 1)))
    (if (i32.eqz (call $is_request)) (then (return (i32.const 0))))
    (global.set $requests (i32.add (global.get $requests) (i32.const 1)))
    (if (i32.eq (global.get $requests) (i32.const 1))
      (then
        (call $output_set (call $block (i32.const 16) (i32.const 116)) (i64.const 116))
        (return (i32.const 0))))
    (i32.store8 (i32.const 289) (i32.add (i32.const 48) (global.get $calls)))
    (call $output_set (call $block (i32.const 256) (i32.const 35)) (i64.const 35))
    (i32.const 0)))
