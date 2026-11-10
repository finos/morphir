;; A morphir-bytes-v1 module that exports handle as () -> i64 instead of
;; () -> i32.
;; Cases: classification/handle-other-type
(module
  (import "morphir_bytes_v1" "input_len" (func (result i32)))
  (func (export "handle") (result i64)
    (i64.const 0)))
