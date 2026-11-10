;; A morphir-bytes-v1 module with two memories (multi-memory feature).
;; Cases: classification/two-memories
(module
  (import "morphir_bytes_v1" "input_len" (func (result i32)))
  (memory 1)
  (memory 1)
  (func (export "handle") (result i32)
    (i32.const -1)))
