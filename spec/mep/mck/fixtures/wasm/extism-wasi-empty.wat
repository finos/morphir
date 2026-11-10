;; An extism-kernel-v1 guest that asks WASI for its arguments, environment,
;; stdin and fd 3 preopen. It answers {"jsonrpc":"2.0","id":1,"result":"tttt"}
;; when, in order: the argument count and size are 0; the environment count
;; and size are 0; a read of stdin gives 0 bytes; fd_prestat_get of fd 3
;; returns a non-zero errno. A failed check leaves its "f".
;; Cases: sandbox/wasi-empty-world
(module
  (import "extism:host/env" "alloc" (func $alloc (param i64) (result i64)))
  (import "extism:host/env" "store_u8" (func $store_u8 (param i64 i32)))
  (import "extism:host/env" "output_set" (func $output_set (param i64 i64)))
  (import "wasi_snapshot_preview1" "args_sizes_get" (func $args_sizes_get (param i32 i32) (result i32)))
  (import "wasi_snapshot_preview1" "environ_sizes_get" (func $environ_sizes_get (param i32 i32) (result i32)))
  (import "wasi_snapshot_preview1" "fd_read" (func $fd_read (param i32 i32 i32 i32) (result i32)))
  (import "wasi_snapshot_preview1" "fd_prestat_get" (func $fd_prestat_get (param i32 i32) (result i32)))
  (memory (export "memory") 1)
  ;; One iovec at 16: 16 bytes at 128.
  (data (i32.const 16) "\80\00\00\00\10\00\00\00")
  ;; 40 bytes; the flags are at 1058 to 1061.
  (data (i32.const 1024) "{\22jsonrpc\22:\222.0\22,\22id\22:1,\22result\22:\22ffff\22}")
  ;; Copies $len bytes of guest memory at $ptr into a new kernel block.
  (func $block (param $ptr i32) (param $len i32) (result i64)
    (local $h i64) (local $i i32)
    (local.set $h (call $alloc (i64.extend_i32_u (local.get $len))))
    (block $copied
      (loop $copy
        (br_if $copied (i32.ge_u (local.get $i) (local.get $len)))
        (call $store_u8
          (i64.add (local.get $h) (i64.extend_i32_u (local.get $i)))
          (i32.load8_u (i32.add (local.get $ptr) (local.get $i))))
        (local.set $i (i32.add (local.get $i) (i32.const 1)))
        (br $copy)))
    (local.get $h))
  (func (export "handle") (result i32)
    (drop (call $args_sizes_get (i32.const 0) (i32.const 4)))
    (drop (call $environ_sizes_get (i32.const 8) (i32.const 12)))
    (drop (call $fd_read (i32.const 0) (i32.const 16) (i32.const 1) (i32.const 24)))
    (if (i32.eqz (i32.or (i32.load (i32.const 0)) (i32.load (i32.const 4))))
      (then (i32.store8 (i32.const 1058) (i32.const 116))))
    (if (i32.eqz (i32.or (i32.load (i32.const 8)) (i32.load (i32.const 12))))
      (then (i32.store8 (i32.const 1059) (i32.const 116))))
    (if (i32.eqz (i32.load (i32.const 24)))
      (then (i32.store8 (i32.const 1060) (i32.const 116))))
    (if (call $fd_prestat_get (i32.const 3) (i32.const 32))
      (then (i32.store8 (i32.const 1061) (i32.const 116))))
    (call $output_set (call $block (i32.const 1024) (i32.const 40)) (i64.const 40))
    (i32.const 0)))
