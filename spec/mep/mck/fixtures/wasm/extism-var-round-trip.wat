;; An extism-kernel-v1 guest that reads the Extism var "k". When "k" holds the
;; 44 bytes {"jsonrpc":"2.0","id":2,"result":"from-var"} it answers with them.
;; Otherwise it stores them in "k" and answers
;; {"jsonrpc":"2.0","id":1,"result":"stored"}.
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
    (if (i64.ne (local.get $value) (i64.const 0))
      (then
        (if (i64.eq (call $length (local.get $value)) (i64.const 44))
          (then
            (call $output_set (local.get $value) (i64.const 44))
            (return (i32.const 0))))))
    (call $var_set (call $block (i32.const 0) (i32.const 1)) (call $block (i32.const 128) (i32.const 44)))
    (call $output_set (call $block (i32.const 64) (i32.const 42)) (i64.const 42))
    (i32.const 0)))
