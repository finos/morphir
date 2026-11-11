;; Imports an Extism kernel function and exports run, not handle.
;; Cases: classification/missing-handle
(module
  (import "extism:host/env" "input_length" (func (result i64)))
  (func (export "run") (result i32)
    (i32.const 0)))
