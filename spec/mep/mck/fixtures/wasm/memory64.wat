;; An extism-kernel-v1 module with a 64-bit memory (memory64 feature).
;; Cases: classification/memory64
(module
  (import "extism:host/env" "input_length" (func (result i64)))
  (memory i64 1)
  (func (export "handle") (result i32)
    (i32.const 1)))
