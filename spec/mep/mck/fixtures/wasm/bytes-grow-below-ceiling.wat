;; Starts with 1600 pages (100 MiB) and asks for 3200 more (200 MiB), which
;; the 256 MiB ceiling cannot grant. When the growth is refused it executes
;; unreachable; if the growth were granted it would return -1.
;; Cases: bounds/grow-refused-below-ceiling
(module
  (import "morphir_bytes_v1" "input_len" (func (result i32)))
  (memory 1600)
  (func (export "handle") (result i32)
    (if (i32.eq (memory.grow (i32.const 3200)) (i32.const -1)) (then unreachable))
    (i32.const -1)))
