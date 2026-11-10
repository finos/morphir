;; Imports morphir_bytes_v1.input_byte as (i64) -> i32; the profile has it
;; as (i32) -> i32.
;; Cases: classification/known-name-other-signature
(module
  (import "morphir_bytes_v1" "input_byte" (func (param i64) (result i32)))
  (func (export "handle") (result i32)
    (i32.const -1)))
