;; A morphir-bytes-v1 module whose initial memory is 4097 pages, one page
;; above the 256 MiB ceiling.
;; Cases: bounds/initial-memory-over-ceiling
(module
  (import "morphir_bytes_v1" "input_len" (func (result i32)))
  (memory 4097)
  (func (export "handle") (result i32)
    (i32.const -1)))
