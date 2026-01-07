// Package vfs provides virtual filesystem abstractions that can be backed by
// in-memory data structures or on-disk filesystems.
//
// # Mounts and Permissions
//
// The VFS supports multiple mounts with precedence ordering. Each mount can be
// read-only (RO) or read-write (RW). Write operations are scoped to specific mounts.
//
// # Write Policies
//
// Write operations can be restricted using policy hooks. Policies evaluate write
// requests and can allow, deny, or skip to the next policy in a chain.
//
// Built-in policies include:
//   - PathPrefixPolicy: Restricts writes to specific path prefixes
//   - ReadOnlyPathPolicy: Denies writes to specific paths
//   - PolicyChain: Combines multiple policies with AND semantics
//
// Example usage:
//
//	policy := vfs.NewPolicyChain(
//	    &vfs.PathPrefixPolicy{AllowedPrefixes: []string{"/workspace"}},
//	    &vfs.ReadOnlyPathPolicy{ReadOnlyPaths: []string{"/workspace/.git"}},
//	)
//	writer, err := vfs.WriterWithPolicy(policy)
//
// # Metadata
//
// OS-backed entries attach metadata under "os.*" keys in Meta.Dynamic, including:
// - os.path (string)
// - os.is_dir (bool)
// - os.mode (string)
// - os.size (int64)
// - os.mod_time (RFC3339 string)
package vfs
