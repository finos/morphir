;; A morphir-bytes-v1 module with a shared memory (threads feature).
;; Cases: classification/shared-memory
(module
  (import "morphir_bytes_v1" "input_len" (func (result i32)))
  (memory 1 1 shared)
  (func (export "handle") (result i32)
    (i32.const -1)))
