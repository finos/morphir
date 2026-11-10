;; An extism-kernel-v1 module with a shared memory (threads feature).
;; Cases: classification/shared-memory
(module
  (import "extism:host/env" "input_length" (func (result i64)))
  (memory 1 1 shared)
  (func (export "handle") (result i32)
    (i32.const 1)))
