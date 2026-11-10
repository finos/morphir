;; A morphir-bytes-v1 guest whose handle returns 0, the exit code, for every
;; message.
;; Cases: bytes/exit
(module
  (import "morphir_bytes_v1" "input_len" (func (result i32)))
  (func (export "handle") (result i32)
    (i32.const 0)))
