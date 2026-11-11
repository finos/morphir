;; A morphir-bytes-v1 guest that pushes the bytes FF FE, which are not UTF-8,
;; and returns their length, 2.
;; Cases: bytes/response-not-utf8
(module
  (import "morphir_bytes_v1" "output_byte" (func $output_byte (param i32)))
  (func (export "handle") (result i32)
    (call $output_byte (i32.const 0xff))
    (call $output_byte (i32.const 0xfe))
    (i32.const 2)))
