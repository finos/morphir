;; An extism-kernel-v1 guest whose handle loops forever.
;; Cases: bounds/spin-extism, bounds/small-budget
(module
  (import "extism:host/env" "input_length" (func (result i64)))
  (func (export "handle") (result i32)
    (loop $spin (br $spin))
    (i32.const 1)))
