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
// # Traversal Helpers
//
// The VFS provides flexible traversal helpers for walking, filtering, mapping, and
// folding over filesystem entries.
//
// Entry-level traversal (traverse.go):
//   - Walk: Pre/post-order traversal with skip and stop control
//   - Filter: Select entries matching a predicate
//   - Map/MapSame: Transform entries recursively
//   - Fold: Accumulate values across entries
//
// VFS-level traversal (vfs_traverse.go):
//   - VFSWalk: Traverse with shadowed entry support
//   - VFSFilter: Filter entries through VFS resolution
//   - VFSMap/VFSFold: Transform/accumulate with shadow awareness
//   - VFSCollect: Gather all entries under a path
//   - VFSFindFiles/VFSFindFolders: Type-specific searches
//   - VFSWalkGlob/VFSCollectGlob: Pattern-based traversal
//
// Example traversal:
//
//	err := vfs.VFSWalk(vfs, vfs.MustVPath("/workspace"), vfs.VFSWalkOptions{},
//	    func(e vfs.Entry, shadowed bool) (vfs.WalkControl, error) {
//	        fmt.Println(e.Path())
//	        return vfs.WalkContinue, nil
//	    },
//	    nil,
//	)
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
