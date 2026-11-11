;; Imports extism:host/env.input_length first and morphir_bytes_v1.input_len
;; second. The first import decides the profile, extism-kernel-v1, and the
;; second is then outside that profile's surface.
;; Cases: classification/first-import-decides
(module
  (import "extism:host/env" "input_length" (func (result i64)))
  (import "morphir_bytes_v1" "input_len" (func (result i32)))
  (func (export "handle") (result i32)
    (i32.const 0)))
