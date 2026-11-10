;; An extism-kernel-v1 guest that grows its memory until the host refuses a
;; growth of one page, then executes unreachable. It asks for 2048 pages at a
;; time and halves the request after each refusal, so it stops exactly at the
;; ceiling after about a dozen growths. Growing one page at a time made a slow
;; engine miss the call deadline. The memory declares no maximum.
;; Cases: bounds/grow-to-ceiling-then-trap
(module
  (import "extism:host/env" "input_length" (func (result i64)))
  (memory 1)
  (func (export "handle") (result i32)
    (local $step i32)
    (local.set $step (i32.const 2048))
    (loop $grow
      (if (i32.eq (memory.grow (local.get $step)) (i32.const -1))
        (then (local.set $step (i32.shr_u (local.get $step) (i32.const 1)))))
      (br_if $grow (local.get $step)))
    unreachable))
