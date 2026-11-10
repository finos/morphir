;; A morphir-bytes-v1 guest whose handle returns -2, the notification code,
;; for every message, also for a request.
;; Cases: bytes/notification-code-for-request
(module
  (import "morphir_bytes_v1" "input_len" (func (result i32)))
  (func (export "handle") (result i32)
    (i32.const -2)))
