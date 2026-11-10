;; Imports morphir_get_workspace_info as (i64) -> i64; the profile has it as
;; () -> i64.
;; Cases: classification/workspace-info-with-param
(module
  (import "extism:host/user" "morphir_get_workspace_info" (func (param i64) (result i64)))
  (func (export "handle") (result i32)
    (i32.const 0)))
