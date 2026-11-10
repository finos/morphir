;; An extism-kernel-v1 guest that grows its memory one page at a time until
;; the host refuses a growth, then executes unreachable. The memory declares
;; no maximum.
;; Cases: bounds/grow-to-ceiling-then-trap
(module
  (import "extism:host/env" "input_length" (func (result i64)))
  (memory 1)
  (func (export "handle") (result i32)
    (loop $grow
      (br_if $grow (i32.ne (memory.grow (i32.const 1)) (i32.const -1))))
    unreachable))
