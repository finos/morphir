;; An extism-kernel-v1 guest whose handle executes unreachable at once.
;; Cases: bounds/trap, limits/request-over-limit
(module
  (import "extism:host/env" "input_length" (func (result i64)))
  (func (export "handle") (result i32)
    unreachable))
