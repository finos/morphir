package vfs

import (
	"testing"

	"github.com/stretchr/testify/require"
)

func TestPathPrefixPolicy(t *testing.T) {
	policy := &PathPrefixPolicy{
		AllowedPrefixes: []string{"/workspace", "/tmp"},
	}

	tests := []struct {
		name     string
		path     string
		expected PolicyDecision
	}{
		{"exact match", "/workspace", PolicyAllow},
		{"under prefix", "/workspace/file.txt", PolicyAllow},
		{"tmp prefix", "/tmp/data.bin", PolicyAllow},
		{"outside prefix", "/etc/config", PolicyDeny},
		{"partial match not allowed", "/work", PolicyDeny},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			req := WriteRequest{
				Op:   OpCreateFile,
				Path: MustVPath(tt.path),
			}
			result := policy.Evaluate(req)
			require.Equal(t, tt.expected, result.Decision)
		})
	}
}

func TestPathPrefixPolicyEmptyAllowsAll(t *testing.T) {
	policy := &PathPrefixPolicy{AllowedPrefixes: []string{}}

	req := WriteRequest{
		Op:   OpCreateFile,
		Path: MustVPath("/any/path"),
	}
	result := policy.Evaluate(req)
	require.Equal(t, PolicySkip, result.Decision)
}

func TestReadOnlyPathPolicy(t *testing.T) {
	policy := &ReadOnlyPathPolicy{
		ReadOnlyPaths: []string{"/system", "/etc"},
	}

	tests := []struct {
		name     string
		path     string
		expected PolicyDecision
	}{
		{"readonly exact", "/system", PolicyDeny},
		{"readonly subpath", "/system/config", PolicyDeny},
		{"readonly etc", "/etc/passwd", PolicyDeny},
		{"writable path", "/workspace/file.txt", PolicySkip},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			req := WriteRequest{
				Op:   OpUpdateFile,
				Path: MustVPath(tt.path),
			}
			result := policy.Evaluate(req)
			require.Equal(t, tt.expected, result.Decision)
		})
	}
}

func TestPolicyChain(t *testing.T) {
	prefixPolicy := &PathPrefixPolicy{
		AllowedPrefixes: []string{"/workspace"},
	}
	readOnlyPolicy := &ReadOnlyPathPolicy{
		ReadOnlyPaths: []string{"/workspace/readonly"},
	}

	chain := NewPolicyChain(prefixPolicy, readOnlyPolicy)

	tests := []struct {
		name     string
		path     string
		expected PolicyDecision
	}{
		{"allowed and writable", "/workspace/file.txt", PolicyAllow},
		{"allowed but readonly", "/workspace/readonly/config", PolicyDeny},
		{"outside workspace", "/tmp/file.txt", PolicyDeny},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			req := WriteRequest{
				Op:   OpCreateFile,
				Path: MustVPath(tt.path),
			}
			result := chain.Evaluate(req)
			require.Equal(t, tt.expected, result.Decision)
			if result.Decision == PolicyDeny {
				require.NotEmpty(t, result.Reason)
			}
		})
	}
}

func TestWriterWithPolicy(t *testing.T) {
	root := NewMemFolder(MustVPath("/"), Meta{}, Origin{MountName: "mem"}, nil)
	vfs := NewOverlayVFS([]Mount{{Name: "mem", Mode: MountRW, Root: root}})

	policy := &PathPrefixPolicy{
		AllowedPrefixes: []string{"/workspace"},
	}

	writer, err := vfs.WriterWithPolicy(policy)
	require.NoError(t, err)

	// Should succeed - within allowed prefix
	_, err = writer.CreateFile(MustVPath("/workspace/file.txt"), []byte("data"), WriteOptions{MkdirParents: true})
	require.NoError(t, err)

	// Should fail - outside allowed prefix
	_, err = writer.CreateFile(MustVPath("/etc/passwd"), []byte("data"), WriteOptions{MkdirParents: true})
	require.Error(t, err)
	require.True(t, IsPolicyDenied(err))
}

func TestWriterWithPolicyReadOnly(t *testing.T) {
	root := NewMemFolder(MustVPath("/"), Meta{}, Origin{MountName: "mem"}, nil)
	vfs := NewOverlayVFS([]Mount{{Name: "mem", Mode: MountRW, Root: root}})

	policy := &ReadOnlyPathPolicy{
		ReadOnlyPaths: []string{"/system"},
	}

	writer, err := vfs.WriterWithPolicy(policy)
	require.NoError(t, err)

	// Should succeed - not in readonly paths
	_, err = writer.CreateFolder(MustVPath("/workspace"), WriteOptions{})
	require.NoError(t, err)

	// Should fail - in readonly path
	_, err = writer.CreateFolder(MustVPath("/system/config"), WriteOptions{MkdirParents: true})
	require.Error(t, err)
	require.True(t, IsPolicyDenied(err))
}

func TestWriterWithPolicyChain(t *testing.T) {
	root := NewMemFolder(MustVPath("/"), Meta{}, Origin{MountName: "mem"}, nil)
	vfs := NewOverlayVFS([]Mount{{Name: "mem", Mode: MountRW, Root: root}})

	policy := NewPolicyChain(
		&PathPrefixPolicy{AllowedPrefixes: []string{"/workspace"}},
		&ReadOnlyPathPolicy{ReadOnlyPaths: []string{"/workspace/.git"}},
	)

	writer, err := vfs.WriterWithPolicy(policy)
	require.NoError(t, err)

	// Should succeed - in workspace, not readonly
	_, err = writer.CreateFile(MustVPath("/workspace/src/main.go"), []byte("package main"), WriteOptions{MkdirParents: true})
	require.NoError(t, err)

	// Should fail - in readonly .git directory
	_, err = writer.UpdateFile(MustVPath("/workspace/.git/config"), []byte("modified"), WriteOptions{})
	require.Error(t, err)
	require.True(t, IsPolicyDenied(err))

	// Should fail - outside workspace
	_, err = writer.CreateFile(MustVPath("/tmp/temp.txt"), []byte("temp"), WriteOptions{MkdirParents: true})
	require.Error(t, err)
	require.True(t, IsPolicyDenied(err))
}

func TestTransactionWithPolicy(t *testing.T) {
	root := NewMemFolder(MustVPath("/"), Meta{}, Origin{MountName: "mem"}, nil)
	vfs := NewOverlayVFS([]Mount{{Name: "mem", Mode: MountRW, Root: root}})

	policy := &PathPrefixPolicy{
		AllowedPrefixes: []string{"/workspace"},
	}

	writer, err := vfs.WriterWithPolicy(policy)
	require.NoError(t, err)

	tx, err := writer.Begin()
	require.NoError(t, err)

	// Should succeed
	_, err = tx.CreateFolder(MustVPath("/workspace"), WriteOptions{})
	require.NoError(t, err)

	// Should fail - outside allowed prefix
	_, err = tx.CreateFile(MustVPath("/etc/shadow"), []byte("data"), WriteOptions{MkdirParents: true})
	require.Error(t, err)
	require.True(t, IsPolicyDenied(err))

	// Transaction should still be valid
	err = tx.Rollback()
	require.NoError(t, err)
}

func TestWriterWithPolicyAllOperations(t *testing.T) {
	root := NewMemFolder(MustVPath("/"), Meta{}, Origin{MountName: "mem"}, []Entry{
		NewMemFolder(MustVPath("/workspace"), Meta{}, Origin{MountName: "mem"}, []Entry{
			NewMemFile(MustVPath("/workspace/old.txt"), Meta{}, Origin{MountName: "mem"}, []byte("old")),
		}),
	})
	vfs := NewOverlayVFS([]Mount{{Name: "mem", Mode: MountRW, Root: root}})

	policy := &PathPrefixPolicy{
		AllowedPrefixes: []string{"/workspace"},
	}

	writer, err := vfs.WriterWithPolicy(policy)
	require.NoError(t, err)

	// Test Update
	_, err = writer.UpdateFile(MustVPath("/workspace/old.txt"), []byte("new"), WriteOptions{})
	require.NoError(t, err)

	// Test Move within workspace
	_, err = writer.Move(MustVPath("/workspace/old.txt"), MustVPath("/workspace/new.txt"), WriteOptions{})
	require.NoError(t, err)

	// Test Delete
	_, err = writer.Delete(MustVPath("/workspace/new.txt"))
	require.NoError(t, err)

	// Test Move to outside workspace (should fail)
	_, err = writer.CreateFile(MustVPath("/workspace/test.txt"), []byte("test"), WriteOptions{})
	require.NoError(t, err)

	_, err = writer.Move(MustVPath("/workspace/test.txt"), MustVPath("/etc/test.txt"), WriteOptions{})
	require.Error(t, err)
	require.True(t, IsPolicyDenied(err))
}
