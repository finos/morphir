;; An extism-kernel-v1 guest that imports morphir_get_workspace_info as
;; () -> i64, calls it, and answers {"jsonrpc":"2.0","id":1,"result":<info>}
;; with the returned bytes as <info>.
;; Cases: sandbox/workspace-info
(module
  (import "extism:host/env" "alloc" (func $alloc (param i64) (result i64)))
  (import "extism:host/env" "store_u8" (func $store_u8 (param i64 i32)))
  (import "extism:host/env" "load_u8" (func $load_u8 (param i64) (result i32)))
  (import "extism:host/env" "length" (func $length (param i64) (result i64)))
  (import "extism:host/env" "output_set" (func $output_set (param i64 i64)))
  (import "extism:host/user" "morphir_get_workspace_info" (func $workspace_info (result i64)))
  (memory 1)
  ;; 33 bytes.
  (data (i32.const 0) "{\22jsonrpc\22:\222.0\22,\22id\22:1,\22result\22:")
  (func (export "handle") (result i32)
    (local $info i64) (local $n i64) (local $out i64) (local $i i64)
    (local.set $info (call $workspace_info))
    (local.set $n (call $length (local.get $info)))
    (local.set $out (call $alloc (i64.add (local.get $n) (i64.const 34))))
    (block $prefixed
      (loop $prefix
        (br_if $prefixed (i64.ge_u (local.get $i) (i64.const 33)))
        (call $store_u8 (i64.add (local.get $out) (local.get $i))
          (i32.load8_u (i32.wrap_i64 (local.get $i))))
        (local.set $i (i64.add (local.get $i) (i64.const 1)))
        (br $prefix)))
    (local.set $i (i64.const 0))
    (block $copied
      (loop $copy
        (br_if $copied (i64.ge_u (local.get $i) (local.get $n)))
        (call $store_u8 (i64.add (local.get $out) (i64.add (i64.const 33) (local.get $i)))
          (call $load_u8 (i64.add (local.get $info) (local.get $i))))
        (local.set $i (i64.add (local.get $i) (i64.const 1)))
        (br $copy)))
    (call $store_u8 (i64.add (local.get $out) (i64.add (i64.const 33) (local.get $n))) (i32.const 125))
    (call $output_set (local.get $out) (i64.add (local.get $n) (i64.const 34)))
    (i32.const 0)))
