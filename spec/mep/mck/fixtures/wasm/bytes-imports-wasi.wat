;; Imports the three byte callbacks and wasi_snapshot_preview1.fd_write. The
;; byte profile has no WASI.
;; Cases: classification/byte-module-imports-wasi
(module
  (import "morphir_bytes_v1" "input_len" (func (result i32)))
  (import "morphir_bytes_v1" "input_byte" (func (param i32) (result i32)))
  (import "morphir_bytes_v1" "output_byte" (func (param i32)))
  (import "wasi_snapshot_preview1" "fd_write" (func (param i32 i32 i32 i32) (result i32)))
  (memory 1)
  (func (export "handle") (result i32)
    (i32.const -1)))
