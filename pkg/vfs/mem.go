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

func (f MemFile) Path() VPath     { return f.path }
func (f MemFile) Kind() EntryKind { return KindFile }
func (f MemFile) Meta() Meta      { return cloneMeta(f.meta) }
func (f MemFile) Origin() Origin  { return f.origin }
func (f MemFile) Bytes() ([]byte, error) {
	return cloneBytes(f.data), nil
}
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

func (f MemFolder) Path() VPath     { return f.path }
func (f MemFolder) Kind() EntryKind { return KindFolder }
func (f MemFolder) Meta() Meta      { return cloneMeta(f.meta) }
func (f MemFolder) Origin() Origin  { return f.origin }
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

func (n MemNode) Path() VPath      { return n.path }
func (n MemNode) Kind() EntryKind  { return KindNode }
func (n MemNode) Meta() Meta       { return cloneMeta(n.meta) }
func (n MemNode) Origin() Origin   { return n.origin }
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

func (d MemDocument) Kind() EntryKind { return KindDocument }
func (d MemDocument) Root() Node      { return d.root }

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

func (a MemArchive) Path() VPath     { return a.path }
func (a MemArchive) Kind() EntryKind { return KindArchive }
func (a MemArchive) Meta() Meta      { return cloneMeta(a.meta) }
func (a MemArchive) Origin() Origin  { return a.origin }
func (a MemArchive) Bytes() ([]byte, error) {
	return cloneBytes(a.data), nil
}
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
