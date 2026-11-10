;; A well-behaved morphir-bytes-v1 guest. It copies the message to offset 64.
;; A message that contains "id" is a request and is answered with its own
;; bytes; a message that contains morphir.exit returns 0; any other message
;; is a notification and returns -2.
;; Cases: bytes/echo, bytes/notification-consumed, classification/bytes-profile-unsupported
(module
  (import "morphir_bytes_v1" "input_len" (func $input_len (result i32)))
  (import "morphir_bytes_v1" "input_byte" (func $input_byte (param i32) (result i32)))
  (import "morphir_bytes_v1" "output_byte" (func $output_byte (param i32)))
  (memory 1)
  (data (i32.const 0) "\22id\22")
  (data (i32.const 8) "morphir.exit")
  ;; 1 when the $size bytes at $at occur in the $len bytes of the message.
  (func $contains (param $at i32) (param $size i32) (param $len i32) (result i32)
    (local $i i32) (local $j i32)
    (loop $start
      (if (i32.gt_u (i32.add (local.get $i) (local.get $size)) (local.get $len))
        (then (return (i32.const 0))))
      (local.set $j (i32.const 0))
      (block $differs
        (loop $compare
          (if (i32.eq (local.get $j) (local.get $size)) (then (return (i32.const 1))))
          (br_if $differs
            (i32.ne
              (i32.load8_u (i32.add (i32.const 64) (i32.add (local.get $i) (local.get $j))))
              (i32.load8_u (i32.add (local.get $at) (local.get $j)))))
          (local.set $j (i32.add (local.get $j) (i32.const 1)))
          (br $compare)))
      (local.set $i (i32.add (local.get $i) (i32.const 1)))
      (br $start))
    (i32.const 0))
  (func (export "handle") (result i32)
    (local $len i32) (local $i i32)
    (local.set $len (call $input_len))
    (block $copied
      (loop $copy
        (br_if $copied (i32.ge_u (local.get $i) (local.get $len)))
        (i32.store8 (i32.add (i32.const 64) (local.get $i)) (call $input_byte (local.get $i)))
        (local.set $i (i32.add (local.get $i) (i32.const 1)))
        (br $copy)))
    (if (i32.eqz (call $contains (i32.const 0) (i32.const 4) (local.get $len)))
      (then
        (return
          (select (i32.const 0) (i32.const -2)
            (call $contains (i32.const 8) (i32.const 12) (local.get $len))))))
    (local.set $i (i32.const 0))
    (block $written
      (loop $write
        (br_if $written (i32.ge_u (local.get $i) (local.get $len)))
        (call $output_byte (i32.load8_u (i32.add (i32.const 64) (local.get $i))))
        (local.set $i (i32.add (local.get $i) (i32.const 1)))
        (br $write)))
    (local.get $len)))
