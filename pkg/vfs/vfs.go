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
}
