;; Imports env.open_socket, which no profile has.
;; Cases: classification/unknown-namespace
(module
  (import "env" "open_socket" (func (param i32 i32) (result i32)))
  (func (export "handle") (result i32)
    (i32.const 0)))
