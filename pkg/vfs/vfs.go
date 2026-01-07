// Package vfs provides a virtual filesystem abstraction for Morphir pipelines.
package vfs

import "io"

// EntryKind describes the kind of a VEntry.
type EntryKind string

const (
	KindFile     EntryKind = "file"
	KindFolder   EntryKind = "folder"
	KindDocument EntryKind = "document"
	KindNode     EntryKind = "node"
	KindArchive  EntryKind = "archive"
)

// Meta stores dynamic and typed metadata for entries.
type Meta struct {
	Dynamic map[string]any
	Typed   map[string]any
}

// Origin tracks which mount an entry came from.
type Origin struct {
	MountName string
}

// Entry is the common interface for all VFS entries.
type Entry interface {
	Path() VPath
	Kind() EntryKind
	Meta() Meta
	Origin() Origin
}

// File is a leaf entry that can provide content.
type File interface {
	Entry
	Bytes() ([]byte, error)
	Stream() (io.ReadCloser, error)
}

// Folder is a container entry with children.
type Folder interface {
	Entry
	Children() ([]Entry, error)
}

// Document is a file with a hierarchical root node.
type Document interface {
	File
	Root() Node
}

// Node represents a hierarchical document node.
type Node interface {
	Entry
	NodeType() string
	Attrs() map[string]any
	Children() []Node
}

// Archive is a container artifact that can be expanded.
type Archive interface {
	Entry
	Bytes() ([]byte, error)
	Exploded() (Folder, bool)
}

// MountMode defines mount access permissions.
type MountMode string

const (
	MountRO MountMode = "ro"
	MountRW MountMode = "rw"
)

// Mount represents a mounted filesystem root.
type Mount struct {
	Name string
	Mode MountMode
	Root Folder
}

// ShadowedEntry represents a hidden entry from a lower-precedence mount.
type ShadowedEntry struct {
	Entry       Entry
	Mount       Mount
	Reason      string
	ShadowedBy  string
	VisiblePath VPath
}

// ListOptions configures directory listing.
type ListOptions struct {
	IncludeShadowed bool
}

// FindOptions configures glob lookups.
type FindOptions struct {
	IncludeShadowed bool
}

// VFS provides access to mounted entries.
type VFS interface {
	Resolve(path VPath) (Entry, []ShadowedEntry, error)
	List(path VPath, opts ListOptions) ([]Entry, error)
	Find(glob Glob, opts FindOptions) ([]Entry, error)

	Writer() (VFSWriter, error)
	WriterForMount(name string) (VFSWriter, error)
	WriterWithPolicy(policy WritePolicy) (VFSWriter, error)
	WriterForMountWithPolicy(name string, policy WritePolicy) (VFSWriter, error)
}

// WriteOptions configures write behavior.
type WriteOptions struct {
	MkdirParents bool
	Overwrite    bool
}

// VFSWriter performs write operations.
type VFSWriter interface {
	CreateFile(path VPath, data []byte, opts WriteOptions) (Entry, error)
	CreateFolder(path VPath, opts WriteOptions) (Entry, error)
	UpdateFile(path VPath, data []byte, opts WriteOptions) (Entry, error)
	Delete(path VPath) (Entry, error)
	Move(from VPath, to VPath, opts WriteOptions) (Entry, error)
	Begin() (VFSTransaction, error)
}

// VFSTransaction batches write operations.
type VFSTransaction interface {
	CreateFile(path VPath, data []byte, opts WriteOptions) (Entry, error)
	CreateFolder(path VPath, opts WriteOptions) (Entry, error)
	UpdateFile(path VPath, data []byte, opts WriteOptions) (Entry, error)
	Delete(path VPath) (Entry, error)
	Move(from VPath, to VPath, opts WriteOptions) (Entry, error)
	Commit() error
	Rollback() error
}
