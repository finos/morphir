;; An extism-kernel-v1 guest that makes no HTTP request and asks for the
;; status code and the headers of the last one. It answers
;; {"jsonrpc":"2.0","id":1,"result":"tt"} when http_status_code gives 0 and
;; http_headers gives handle 0. A failed check leaves its "f".
;; Cases: sandbox/http-no-request
(module
  (import "extism:host/env" "alloc" (func $alloc (param i64) (result i64)))
  (import "extism:host/env" "store_u8" (func $store_u8 (param i64 i32)))
  (import "extism:host/env" "output_set" (func $output_set (param i64 i64)))
  (import "extism:host/env" "http_status_code" (func $http_status_code (result i32)))
  (import "extism:host/env" "http_headers" (func $http_headers (result i64)))
  (memory 1)
  ;; 38 bytes; the flags are at 1058 and 1059.
  (data (i32.const 1024) "{\22jsonrpc\22:\222.0\22,\22id\22:1,\22result\22:\22ff\22}")
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
    (if (i32.eqz (call $http_status_code))
      (then (i32.store8 (i32.const 1058) (i32.const 116))))
    (if (i64.eqz (call $http_headers))
      (then (i32.store8 (i32.const 1059) (i32.const 116))))
    (call $output_set (call $block (i32.const 1024) (i32.const 38)) (i64.const 38))
    (i32.const 0)))
