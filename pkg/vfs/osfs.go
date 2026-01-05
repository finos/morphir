package vfs

import (
	"io"
	"os"
	"path/filepath"
	"time"
)

// OSFile is a file backed by the local filesystem.
type OSFile struct {
	path   VPath
	meta   Meta
	origin Origin
	osPath string
}

// NewOSFile constructs an OS-backed file entry.
func NewOSFile(path VPath, meta Meta, origin Origin, osPath string) OSFile {
	return OSFile{
		path:   path,
		meta:   cloneMeta(meta),
		origin: origin,
		osPath: osPath,
	}
}

func (f OSFile) Path() VPath     { return f.path }
func (f OSFile) Kind() EntryKind { return KindFile }
func (f OSFile) Meta() Meta      { return cloneMeta(f.meta) }
func (f OSFile) Origin() Origin  { return f.origin }
func (f OSFile) Bytes() ([]byte, error) {
	return os.ReadFile(f.osPath)
}
func (f OSFile) Stream() (io.ReadCloser, error) {
	return os.Open(f.osPath)
}

// OSFolder is a folder backed by the local filesystem.
type OSFolder struct {
	path   VPath
	meta   Meta
	origin Origin
	osPath string
}

// NewOSFolder constructs an OS-backed folder entry.
func NewOSFolder(path VPath, meta Meta, origin Origin, osPath string) OSFolder {
	return OSFolder{
		path:   path,
		meta:   cloneMeta(meta),
		origin: origin,
		osPath: osPath,
	}
}

func (f OSFolder) Path() VPath     { return f.path }
func (f OSFolder) Kind() EntryKind { return KindFolder }
func (f OSFolder) Meta() Meta      { return cloneMeta(f.meta) }
func (f OSFolder) Origin() Origin  { return f.origin }
func (f OSFolder) Children() ([]Entry, error) {
	entries, err := os.ReadDir(f.osPath)
	if err != nil {
		return nil, err
	}

	out := make([]Entry, 0, len(entries))
	for _, entry := range entries {
		childPath, err := f.path.Join(entry.Name())
		if err != nil {
			return nil, err
		}
		childOSPath := filepath.Join(f.osPath, entry.Name())
		info, err := entry.Info()
		if err != nil {
			return nil, err
		}
		childMeta := metaWithOSInfo(f.meta, info, childOSPath)

		if entry.IsDir() {
			out = append(out, NewOSFolder(childPath, childMeta, f.origin, childOSPath))
			continue
		}
		out = append(out, NewOSFile(childPath, childMeta, f.origin, childOSPath))
	}

	return out, nil
}

// NewOSMount constructs a Mount backed by a local filesystem root.
func NewOSMount(name string, mode MountMode, rootPath string, mountPath VPath) Mount {
	root := NewOSFolder(mountPath, Meta{}, Origin{MountName: name}, rootPath)
	return Mount{
		Name: name,
		Mode: mode,
		Root: root,
	}
}

func metaWithOSInfo(base Meta, info os.FileInfo, osPath string) Meta {
	meta := cloneMeta(base)
	if meta.Dynamic == nil {
		meta.Dynamic = make(map[string]any)
	}

	meta.Dynamic["os.path"] = osPath
	if info == nil {
		return meta
	}

	meta.Dynamic["os.is_dir"] = info.IsDir()
	meta.Dynamic["os.mode"] = info.Mode().String()
	meta.Dynamic["os.size"] = info.Size()
	meta.Dynamic["os.mod_time"] = info.ModTime().UTC().Format(time.RFC3339)
	return meta
}
