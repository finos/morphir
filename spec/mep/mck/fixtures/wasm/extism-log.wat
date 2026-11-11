;; An extism-kernel-v1 guest that reads get_log_level, logs one marker at each
;; of the five levels with log_trace to log_error, and logs one more with
;; morphir_log at the level "trace". It answers
;; {"jsonrpc":"2.0","id":1,"result":"level-n"}, where n is the digit of the
;; log level it read.
;; Cases: sandbox/logging
(module
  (import "extism:host/env" "alloc" (func $alloc (param i64) (result i64)))
  (import "extism:host/env" "store_u8" (func $store_u8 (param i64 i32)))
  (import "extism:host/env" "output_set" (func $output_set (param i64 i64)))
  (import "extism:host/env" "get_log_level" (func $get_log_level (result i32)))
  (import "extism:host/env" "log_trace" (func $log_trace (param i64)))
  (import "extism:host/env" "log_debug" (func $log_debug (param i64)))
  (import "extism:host/env" "log_info" (func $log_info (param i64)))
  (import "extism:host/env" "log_warn" (func $log_warn (param i64)))
  (import "extism:host/env" "log_error" (func $log_error (param i64)))
  (import "extism:host/user" "morphir_log" (func $morphir_log (param i64 i64)))
  (memory 1)
  ;; Each marker is 16 bytes.
  (data (i32.const 0) "kit-trace-marker")
  (data (i32.const 16) "kit-debug-marker")
  (data (i32.const 32) "kit-info--marker")
  (data (i32.const 48) "kit-warn--marker")
  (data (i32.const 64) "kit-error-marker")
  (data (i32.const 80) "kit-morph-marker")
  (data (i32.const 96) "trace")
  ;; 43 bytes; the digit is at 128 + 40.
  (data (i32.const 128) "{\22jsonrpc\22:\222.0\22,\22id\22:1,\22result\22:\22level-0\22}")
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
    (i32.store8 (i32.const 168) (i32.add (i32.const 48) (call $get_log_level)))
    (call $log_trace (call $block (i32.const 0) (i32.const 16)))
    (call $log_debug (call $block (i32.const 16) (i32.const 16)))
    (call $log_info (call $block (i32.const 32) (i32.const 16)))
    (call $log_warn (call $block (i32.const 48) (i32.const 16)))
    (call $log_error (call $block (i32.const 64) (i32.const 16)))
    (call $morphir_log (call $block (i32.const 96) (i32.const 5)) (call $block (i32.const 80) (i32.const 16)))
    (call $output_set (call $block (i32.const 128) (i32.const 43)) (i64.const 43))
    (i32.const 0)))
