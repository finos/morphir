;; A morphir-bytes-v1 guest whose handle returns -1, the failure code.
;; Cases: bytes/failure
(module
  (import "morphir_bytes_v1" "input_len" (func (result i32)))
  (func (export "handle") (result i32)
    (i32.const -1)))
