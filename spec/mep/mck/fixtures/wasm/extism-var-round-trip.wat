;; An extism-kernel-v1 guest that reads the Extism var "k".
;; - Handle 0, a missing key: it stores the 44 bytes
;;   {"jsonrpc":"2.0","id":2,"result":"from-var"} in "k" and answers
;;   {"jsonrpc":"2.0","id":1,"result":"stored"}.
;; - A block of 44 bytes: it deletes "k" with var_set and value handle 0, and
;;   answers with the 44 bytes when var_get then gives handle 0.
;; - Anything else, or a key that survives the delete: it answers
;;   {"jsonrpc":"2.0","id":0,"result":"unexpected"}.
;; Cases: sandbox/var-round-trip
(module
  (import "extism:host/env" "alloc" (func $alloc (param i64) (result i64)))
  (import "extism:host/env" "store_u8" (func $store_u8 (param i64 i32)))
  (import "extism:host/env" "output_set" (func $output_set (param i64 i64)))
  (import "extism:host/env" "length" (func $length (param i64) (result i64)))
  (import "extism:host/env" "var_get" (func $var_get (param i64) (result i64)))
  (import "extism:host/env" "var_set" (func $var_set (param i64 i64)))
  (memory 1)
  (data (i32.const 0) "k")
  (data (i32.const 64) "{\22jsonrpc\22:\222.0\22,\22id\22:1,\22result\22:\22stored\22}")
  (data (i32.const 128) "{\22jsonrpc\22:\222.0\22,\22id\22:2,\22result\22:\22from-var\22}")
  ;; 46 bytes.
  (data (i32.const 192) "{\22jsonrpc\22:\222.0\22,\22id\22:0,\22result\22:\22unexpected\22}")
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
    (local $value i64)
    (local.set $value (call $var_get (call $block (i32.const 0) (i32.const 1))))
    (if (i64.eqz (local.get $value))
      (then
        (call $var_set (call $block (i32.const 0) (i32.const 1)) (call $block (i32.const 128) (i32.const 44)))
        (call $output_set (call $block (i32.const 64) (i32.const 42)) (i64.const 42))
        (return (i32.const 0))))
    (if (i64.eq (call $length (local.get $value)) (i64.const 44))
      (then
        (call $var_set (call $block (i32.const 0) (i32.const 1)) (i64.const 0))
        (if (i64.eqz (call $var_get (call $block (i32.const 0) (i32.const 1))))
          (then
            (call $output_set (local.get $value) (i64.const 44))
            (return (i32.const 0))))))
    (call $output_set (call $block (i32.const 192) (i32.const 46)) (i64.const 46))
    (i32.const 0)))
