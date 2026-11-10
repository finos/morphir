;; A morphir-bytes-v1 guest whose handle loops forever.
;; Cases: bounds/spin-bytes
(module
  (import "morphir_bytes_v1" "input_len" (func (result i32)))
  (memory 1)
  (func (export "handle") (result i32)
    (loop $spin (br $spin))
    (i32.const -1)))
