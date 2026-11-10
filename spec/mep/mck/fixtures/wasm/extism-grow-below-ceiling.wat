;; An extism-kernel-v1 guest that starts with 1600 pages (100 MiB) and asks
;; for 3200 more (200 MiB), which the 256 MiB ceiling cannot grant. When the
;; growth is refused it executes unreachable; were the growth granted it
;; would return -1.
;; Cases: bounds/grow-refused-below-ceiling
(module
  (import "extism:host/env" "input_length" (func (result i64)))
  (memory 1600)
  (func (export "handle") (result i32)
    (if (i32.eq (memory.grow (i32.const 3200)) (i32.const -1)) (then unreachable))
    (i32.const -1)))
