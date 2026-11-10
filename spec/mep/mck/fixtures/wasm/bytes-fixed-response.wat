;; A morphir-bytes-v1 guest that answers every message with the 40-byte
;; response {"jsonrpc":"2.0","id":1,"result":"done"} and returns 40.
;; Cases: limits/response-over-limit
(module
  (import "morphir_bytes_v1" "output_byte" (func $output_byte (param i32)))
  (memory 1)
  (data (i32.const 0) "{\22jsonrpc\22:\222.0\22,\22id\22:1,\22result\22:\22done\22}")
  (func (export "handle") (result i32)
    (local $i i32)
    (block $written
      (loop $write
        (br_if $written (i32.ge_u (local.get $i) (i32.const 40)))
        (call $output_byte (i32.load8_u (local.get $i)))
        (local.set $i (i32.add (local.get $i) (i32.const 1)))
        (br $write)))
    (i32.const 40)))
