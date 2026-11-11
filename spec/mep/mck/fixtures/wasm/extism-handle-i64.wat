;; An extism-kernel-v1 module that exports handle as () -> i64 instead of
;; () -> i32.
;; Cases: classification/handle-other-type
(module
  (import "extism:host/env" "input_length" (func (result i64)))
  (func (export "handle") (result i64)
    (i64.const 0)))
