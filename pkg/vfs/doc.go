// Package vfs provides virtual filesystem abstractions that can be backed by
// in-memory data structures or on-disk filesystems.
//
// OS-backed entries attach metadata under "os.*" keys in Meta.Dynamic, including:
// - os.path (string)
// - os.is_dir (bool)
// - os.mode (string)
// - os.size (int64)
// - os.mod_time (RFC3339 string)
package vfs
