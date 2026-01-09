package vfs

import (
	"errors"
	"fmt"
)

// ErrorCode identifies VFS error categories.
type ErrorCode string

const (
	ErrNotFoundCode      ErrorCode = "not_found"
	ErrNotFolderCode     ErrorCode = "not_folder"
	ErrAlreadyExistsCode ErrorCode = "already_exists"
	ErrReadOnlyMountCode ErrorCode = "read_only_mount"
	ErrMountNotFoundCode ErrorCode = "mount_not_found"
	ErrInvalidPathCode   ErrorCode = "invalid_path"
	ErrConflictCode      ErrorCode = "conflict"
	ErrPolicyDeniedCode  ErrorCode = "policy_denied"
)

// VFSError provides structured error details for VFS operations.
type VFSError struct {
	Code   ErrorCode
	Path   VPath
	Mount  string
	Op     string
	Err    error
	Reason string // Additional context (e.g., for policy denials)
}

// Error implements the error interface, returning a formatted error message
// including the operation, path, error code, and any additional context.
func (e VFSError) Error() string {
	if e.Reason != "" {
		if e.Err != nil {
			return fmt.Sprintf("vfs: %s %s (%s): %s: %v", e.Op, e.Path.String(), e.Code, e.Reason, e.Err)
		}
		return fmt.Sprintf("vfs: %s %s (%s): %s", e.Op, e.Path.String(), e.Code, e.Reason)
	}
	if e.Err != nil {
		return fmt.Sprintf("vfs: %s %s (%s): %v", e.Op, e.Path.String(), e.Code, e.Err)
	}
	return fmt.Sprintf("vfs: %s %s (%s)", e.Op, e.Path.String(), e.Code)
}

// Unwrap returns the underlying error for use with errors.Is and errors.As.
func (e VFSError) Unwrap() error {
	return e.Err
}

// IsNotFound reports whether err is a VFS "not found" error.
func IsNotFound(err error) bool {
	return hasCode(err, ErrNotFoundCode)
}

// IsNotFolder reports whether err is a VFS "not a folder" error.
func IsNotFolder(err error) bool {
	return hasCode(err, ErrNotFolderCode)
}

// IsAlreadyExists reports whether err is a VFS "already exists" error.
func IsAlreadyExists(err error) bool {
	return hasCode(err, ErrAlreadyExistsCode)
}

// IsReadOnlyMount reports whether err is a VFS "read-only mount" error.
func IsReadOnlyMount(err error) bool {
	return hasCode(err, ErrReadOnlyMountCode)
}

// IsMountNotFound reports whether err is a VFS "mount not found" error.
func IsMountNotFound(err error) bool {
	return hasCode(err, ErrMountNotFoundCode)
}

// IsInvalidPath reports whether err is a VFS "invalid path" error.
func IsInvalidPath(err error) bool {
	return hasCode(err, ErrInvalidPathCode)
}

// IsConflict reports whether err is a VFS "conflict" error.
func IsConflict(err error) bool {
	return hasCode(err, ErrConflictCode)
}

// IsPolicyDenied reports whether err is a VFS "policy denied" error.
func IsPolicyDenied(err error) bool {
	return hasCode(err, ErrPolicyDeniedCode)
}

func hasCode(err error, code ErrorCode) bool {
	var vfsErr VFSError
	if !errors.As(err, &vfsErr) {
		return false
	}
	return vfsErr.Code == code
}
