;; Imports nothing and has no memory; handle returns 0 for every message.
;; Its profile comes from the declaration, or the default profile.
;; Cases: classification/no-imports-declared-bytes, worker/missing-abi
(module
  (func (export "handle") (result i32)
    (i32.const 0)))
