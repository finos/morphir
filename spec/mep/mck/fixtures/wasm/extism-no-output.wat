;; An extism-kernel-v1 guest whose handle returns 0 without setting an output
;; or an error.
;; Cases: extism/empty-output
(module
  (import "extism:host/env" "input_length" (func (result i64)))
  (func (export "handle") (result i32)
    (i32.const 0)))
