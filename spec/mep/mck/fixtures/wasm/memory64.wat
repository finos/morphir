;; A morphir-bytes-v1 module with a 64-bit memory (memory64 feature).
;; Cases: classification/memory64
(module
  (import "morphir_bytes_v1" "input_len" (func (result i32)))
  (memory i64 1)
  (func (export "handle") (result i32)
    (i32.const -1)))
