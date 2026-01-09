package vfs

import (
	"bytes"
	"io"
)

// MemFile is an in-memory file entry.
type MemFile struct {
	path   VPath
	meta   Meta
	origin Origin
	data   []byte
}

// NewMemFile constructs an in-memory file with a defensive copy of data.
func NewMemFile(path VPath, meta Meta, origin Origin, data []byte) MemFile {
	return MemFile{
		path:   path,
		meta:   cloneMeta(meta),
		origin: origin,
		data:   cloneBytes(data),
	}
}

// Path returns the virtual path of this file.
func (f MemFile) Path() VPath { return f.path }

// Kind returns KindFile for this entry type.
func (f MemFile) Kind() EntryKind { return KindFile }

// Meta returns a defensive copy of the file's metadata.
func (f MemFile) Meta() Meta { return cloneMeta(f.meta) }

// Origin returns the origin information for this file.
func (f MemFile) Origin() Origin { return f.origin }

// Bytes returns a defensive copy of the file's contents.
func (f MemFile) Bytes() ([]byte, error) {
	return cloneBytes(f.data), nil
}

// Stream returns a read-only stream of the file's contents.
func (f MemFile) Stream() (io.ReadCloser, error) {
	return io.NopCloser(bytes.NewReader(f.data)), nil
}

// MemFolder is an in-memory folder entry.
type MemFolder struct {
	path     VPath
	meta     Meta
	origin   Origin
	children []Entry
}

// NewMemFolder constructs an in-memory folder with a copy of children.
func NewMemFolder(path VPath, meta Meta, origin Origin, children []Entry) MemFolder {
	return MemFolder{
		path:     path,
		meta:     cloneMeta(meta),
		origin:   origin,
		children: cloneEntries(children),
	}
}

// Path returns the virtual path of this folder.
func (f MemFolder) Path() VPath { return f.path }

// Kind returns KindFolder for this entry type.
func (f MemFolder) Kind() EntryKind { return KindFolder }

// Meta returns a defensive copy of the folder's metadata.
func (f MemFolder) Meta() Meta { return cloneMeta(f.meta) }

// Origin returns the origin information for this folder.
func (f MemFolder) Origin() Origin { return f.origin }

// Children returns a defensive copy of the folder's child entries.
func (f MemFolder) Children() ([]Entry, error) {
	return cloneEntries(f.children), nil
}

// MemNode is an in-memory document node.
type MemNode struct {
	path     VPath
	meta     Meta
	origin   Origin
	nodeType string
	attrs    map[string]any
	children []Node
}

// NewMemNode constructs an in-memory node.
func NewMemNode(path VPath, meta Meta, origin Origin, nodeType string, attrs map[string]any, children []Node) MemNode {
	return MemNode{
		path:     path,
		meta:     cloneMeta(meta),
		origin:   origin,
		nodeType: nodeType,
		attrs:    cloneStringAnyMap(attrs),
		children: cloneNodes(children),
	}
}

// Path returns the virtual path of this node.
func (n MemNode) Path() VPath { return n.path }

// Kind returns KindNode for this entry type.
func (n MemNode) Kind() EntryKind { return KindNode }

// Meta returns a defensive copy of the node's metadata.
func (n MemNode) Meta() Meta { return cloneMeta(n.meta) }

// Origin returns the origin information for this node.
func (n MemNode) Origin() Origin { return n.origin }

// NodeType returns the type identifier for this document node.
func (n MemNode) NodeType() string { return n.nodeType }
func (n MemNode) Attrs() map[string]any {
	return cloneStringAnyMap(n.attrs)
}
func (n MemNode) Children() []Node {
	return cloneNodes(n.children)
}

// MemDocument is an in-memory document entry.
type MemDocument struct {
	MemFile
	root Node
}

// NewMemDocument constructs a document with file bytes and a root node.
func NewMemDocument(path VPath, meta Meta, origin Origin, data []byte, root Node) MemDocument {
	return MemDocument{
		MemFile: NewMemFile(path, meta, origin, data),
		root:    root,
	}
}

// Kind returns KindDocument for this entry type.
func (d MemDocument) Kind() EntryKind { return KindDocument }

// Root returns the root node of this document.
func (d MemDocument) Root() Node { return d.root }

// MemArchive is an in-memory archive entry.
type MemArchive struct {
	path     VPath
	meta     Meta
	origin   Origin
	data     []byte
	exploded Folder
}

// NewMemArchive constructs an archive with optional exploded view.
func NewMemArchive(path VPath, meta Meta, origin Origin, data []byte, exploded Folder) MemArchive {
	return MemArchive{
		path:     path,
		meta:     cloneMeta(meta),
		origin:   origin,
		data:     cloneBytes(data),
		exploded: exploded,
	}
}

// Path returns the virtual path of this archive.
func (a MemArchive) Path() VPath { return a.path }

// Kind returns KindArchive for this entry type.
func (a MemArchive) Kind() EntryKind { return KindArchive }

// Meta returns a defensive copy of the archive's metadata.
func (a MemArchive) Meta() Meta { return cloneMeta(a.meta) }

// Origin returns the origin information for this archive.
func (a MemArchive) Origin() Origin { return a.origin }

// Bytes returns a defensive copy of the raw archive contents.
func (a MemArchive) Bytes() ([]byte, error) {
	return cloneBytes(a.data), nil
}

// Exploded returns the exploded folder view of the archive if available.
func (a MemArchive) Exploded() (Folder, bool) {
	if a.exploded == nil {
		return nil, false
	}
	return a.exploded, true
}

func cloneBytes(data []byte) []byte {
	if data == nil {
		return nil
	}
	out := make([]byte, len(data))
	copy(out, data)
	return out
}

func cloneEntries(entries []Entry) []Entry {
	if entries == nil {
		return nil
	}
	out := make([]Entry, len(entries))
	copy(out, entries)
	return out
}

func cloneNodes(nodes []Node) []Node {
	if nodes == nil {
		return nil
	}
	out := make([]Node, len(nodes))
	copy(out, nodes)
	return out
}

func cloneMeta(meta Meta) Meta {
	return Meta{
		Dynamic: cloneStringAnyMap(meta.Dynamic),
		Typed:   cloneStringAnyMap(meta.Typed),
	}
}

func cloneStringAnyMap(src map[string]any) map[string]any {
	if src == nil {
		return nil
	}
	out := make(map[string]any, len(src))
	for k, v := range src {
		out[k] = v
	}
	return out
}
