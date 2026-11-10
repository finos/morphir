;; An extism-kernel-v1 module with two memories (multi-memory feature).
;; Cases: classification/two-memories
(module
  (import "extism:host/env" "input_length" (func (result i64)))
  (memory 1)
  (memory 1)
  (func (export "handle") (result i32)
    (i32.const 1)))
