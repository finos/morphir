;; An extism-kernel-v1 guest that calls config_get for "kit-missing-key" and
;; answers {"jsonrpc":"2.0","id":1,"result":"t"} when it got handle 0, "f"
;; otherwise.
;; Cases: sandbox/config-get
(module
  (import "extism:host/env" "alloc" (func $alloc (param i64) (result i64)))
  (import "extism:host/env" "store_u8" (func $store_u8 (param i64 i32)))
  (import "extism:host/env" "output_set" (func $output_set (param i64 i64)))
  (import "extism:host/env" "config_get" (func $config_get (param i64) (result i64)))
  (memory 1)
  (data (i32.const 0) "kit-missing-key")
  ;; 37 bytes; the flag is at 1058.
  (data (i32.const 1024) "{\22jsonrpc\22:\222.0\22,\22id\22:1,\22result\22:\22f\22}")
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
    (if (i64.eqz (call $config_get (call $block (i32.const 0) (i32.const 15))))
      (then (i32.store8 (i32.const 1058) (i32.const 116))))
    (call $output_set (call $block (i32.const 1024) (i32.const 37)) (i64.const 37))
    (i32.const 0)))
