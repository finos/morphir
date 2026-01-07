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

func (e VFSError) Unwrap() error {
	return e.Err
}

func IsNotFound(err error) bool {
	return hasCode(err, ErrNotFoundCode)
}

func IsNotFolder(err error) bool {
	return hasCode(err, ErrNotFolderCode)
}

func IsAlreadyExists(err error) bool {
	return hasCode(err, ErrAlreadyExistsCode)
}

func IsReadOnlyMount(err error) bool {
	return hasCode(err, ErrReadOnlyMountCode)
}

func IsMountNotFound(err error) bool {
	return hasCode(err, ErrMountNotFoundCode)
}

func IsInvalidPath(err error) bool {
	return hasCode(err, ErrInvalidPathCode)
}

func IsConflict(err error) bool {
	return hasCode(err, ErrConflictCode)
}

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
