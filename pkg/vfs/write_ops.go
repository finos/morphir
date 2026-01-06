package vfs

import (
	"errors"
	"os"
	"path/filepath"
	"strings"
)

func createFile(root Folder, path VPath, data []byte, opts WriteOptions) (Folder, Entry, error) {
	switch r := root.(type) {
	case OSFolder:
		entry, err := osCreateFile(r, path, data, opts)
		return root, entry, err
	case MemFolder:
		return memCreateFile(r, path, data, opts)
	default:
		return root, nil, VFSError{Code: ErrConflictCode, Path: path, Op: "create_file", Err: errors.New("unsupported root")}
	}
}

func createFolder(root Folder, path VPath, opts WriteOptions) (Folder, Entry, error) {
	switch r := root.(type) {
	case OSFolder:
		entry, err := osCreateFolder(r, path, opts)
		return root, entry, err
	case MemFolder:
		return memCreateFolder(r, path, opts)
	default:
		return root, nil, VFSError{Code: ErrConflictCode, Path: path, Op: "create_folder", Err: errors.New("unsupported root")}
	}
}

func updateFile(root Folder, path VPath, data []byte, opts WriteOptions) (Folder, Entry, error) {
	switch r := root.(type) {
	case OSFolder:
		entry, err := osUpdateFile(r, path, data, opts)
		return root, entry, err
	case MemFolder:
		return memUpdateFile(r, path, data, opts)
	default:
		return root, nil, VFSError{Code: ErrConflictCode, Path: path, Op: "update_file", Err: errors.New("unsupported root")}
	}
}

func deleteEntry(root Folder, path VPath) (Folder, Entry, error) {
	switch r := root.(type) {
	case OSFolder:
		entry, err := osDeleteEntry(r, path)
		return root, entry, err
	case MemFolder:
		newRoot, deleted, err := memDeleteEntry(r, path)
		return newRoot, deleted, err
	default:
		return root, nil, VFSError{Code: ErrConflictCode, Path: path, Op: "delete", Err: errors.New("unsupported root")}
	}
}

func moveEntry(root Folder, from VPath, to VPath, opts WriteOptions) (Folder, Entry, error) {
	switch r := root.(type) {
	case OSFolder:
		entry, err := osMoveEntry(r, from, to, opts)
		return root, entry, err
	case MemFolder:
		return memMoveEntry(r, from, to, opts)
	default:
		return root, nil, VFSError{Code: ErrConflictCode, Path: from, Op: "move", Err: errors.New("unsupported root")}
	}
}

func osCreateFile(root OSFolder, path VPath, data []byte, opts WriteOptions) (Entry, error) {
	osPath, err := vpathToOSPath(root, path)
	if err != nil {
		return nil, err
	}
	dir := filepath.Dir(osPath)
	if opts.MkdirParents {
		if err := os.MkdirAll(dir, 0755); err != nil {
			return nil, err
		}
	} else if _, err := os.Stat(dir); err != nil {
		return nil, VFSError{Code: ErrNotFoundCode, Path: path, Op: "create_file", Err: err}
	}

	if _, err := os.Stat(osPath); err == nil && !opts.Overwrite {
		return nil, VFSError{Code: ErrAlreadyExistsCode, Path: path, Op: "create_file"}
	}

	if err := os.WriteFile(osPath, data, 0644); err != nil {
		return nil, err
	}

	return NewOSFile(path, Meta{}, root.origin, osPath), nil
}

func osCreateFolder(root OSFolder, path VPath, opts WriteOptions) (Entry, error) {
	osPath, err := vpathToOSPath(root, path)
	if err != nil {
		return nil, err
	}

	if info, err := os.Stat(osPath); err == nil {
		if !info.IsDir() {
			return nil, VFSError{Code: ErrAlreadyExistsCode, Path: path, Op: "create_folder"}
		}
		return NewOSFolder(path, Meta{}, root.origin, osPath), nil
	}

	if err := os.MkdirAll(osPath, 0755); err != nil {
		return nil, err
	}
	return NewOSFolder(path, Meta{}, root.origin, osPath), nil
}

func osUpdateFile(root OSFolder, path VPath, data []byte, opts WriteOptions) (Entry, error) {
	osPath, err := vpathToOSPath(root, path)
	if err != nil {
		return nil, err
	}
	info, err := os.Stat(osPath)
	if err != nil {
		return nil, VFSError{Code: ErrNotFoundCode, Path: path, Op: "update_file", Err: err}
	}
	if info.IsDir() {
		return nil, VFSError{Code: ErrConflictCode, Path: path, Op: "update_file", Err: errors.New("target is a folder")}
	}
	if err := os.WriteFile(osPath, data, 0644); err != nil {
		return nil, err
	}
	return NewOSFile(path, Meta{}, root.origin, osPath), nil
}

func osDeleteEntry(root OSFolder, path VPath) (Entry, error) {
	osPath, err := vpathToOSPath(root, path)
	if err != nil {
		return nil, err
	}
	info, err := os.Stat(osPath)
	if err != nil {
		return nil, VFSError{Code: ErrNotFoundCode, Path: path, Op: "delete", Err: err}
	}
	var entry Entry
	if info.IsDir() {
		entry = NewOSFolder(path, Meta{}, root.origin, osPath)
	} else {
		entry = NewOSFile(path, Meta{}, root.origin, osPath)
	}
	if err := os.RemoveAll(osPath); err != nil {
		return nil, err
	}
	return entry, nil
}

func osMoveEntry(root OSFolder, from VPath, to VPath, opts WriteOptions) (Entry, error) {
	fromPath, err := vpathToOSPath(root, from)
	if err != nil {
		return nil, err
	}
	toPath, err := vpathToOSPath(root, to)
	if err != nil {
		return nil, err
	}

	if _, err := os.Stat(toPath); err == nil && !opts.Overwrite {
		return nil, VFSError{Code: ErrAlreadyExistsCode, Path: to, Op: "move"}
	}
	if opts.MkdirParents {
		if err := os.MkdirAll(filepath.Dir(toPath), 0755); err != nil {
			return nil, err
		}
	}
	if err := os.Rename(fromPath, toPath); err != nil {
		return nil, err
	}

	info, err := os.Stat(toPath)
	if err != nil {
		return nil, err
	}
	if info.IsDir() {
		return NewOSFolder(to, Meta{}, root.origin, toPath), nil
	}
	return NewOSFile(to, Meta{}, root.origin, toPath), nil
}

func memCreateFile(root MemFolder, path VPath, data []byte, opts WriteOptions) (Folder, Entry, error) {
	segments := splitPath(path)
	if len(segments) == 0 {
		return root, nil, VFSError{Code: ErrInvalidPathCode, Path: path, Op: "create_file"}
	}
	return memCreateFileAt(root, segments, path, data, opts)
}

func memCreateFolder(root MemFolder, path VPath, opts WriteOptions) (Folder, Entry, error) {
	segments := splitPath(path)
	if len(segments) == 0 {
		return root, root, nil
	}
	return memCreateFolderAt(root, segments, path, opts)
}

func memUpdateFile(root MemFolder, path VPath, data []byte, opts WriteOptions) (Folder, Entry, error) {
	entry, ok := memFindEntry(root, path)
	if !ok {
		return root, nil, VFSError{Code: ErrNotFoundCode, Path: path, Op: "update_file"}
	}
	if _, ok := entry.(File); !ok {
		return root, nil, VFSError{Code: ErrConflictCode, Path: path, Op: "update_file", Err: errors.New("target is not file")}
	}
	return memCreateFile(root, path, data, WriteOptions{Overwrite: true, MkdirParents: opts.MkdirParents})
}

func memDeleteEntry(root MemFolder, path VPath) (MemFolder, Entry, error) {
	segments := splitPath(path)
	if len(segments) == 0 {
		return root, nil, VFSError{Code: ErrConflictCode, Path: path, Op: "delete", Err: errors.New("cannot delete root")}
	}
	newRoot, deleted, err := memDeleteAt(root, segments, path)
	if err != nil {
		return root, nil, err
	}
	return newRoot, deleted, nil
}

func memMoveEntry(root MemFolder, from VPath, to VPath, opts WriteOptions) (Folder, Entry, error) {
	newRoot, deleted, err := memDeleteEntry(root, from)
	if err != nil {
		return root, nil, err
	}
	rebased := rebaseEntry(deleted, to)
	return memInsertEntry(newRoot, to, rebased, opts)
}

func memCreateFileAt(folder MemFolder, segments []string, fullPath VPath, data []byte, opts WriteOptions) (Folder, Entry, error) {
	if len(segments) == 1 {
		existing, idx := findChild(folder, segments[0])
		if existing != nil && !opts.Overwrite {
			return folder, nil, VFSError{Code: ErrAlreadyExistsCode, Path: fullPath, Op: "create_file"}
		}
		newFile := NewMemFile(fullPath, Meta{}, folder.origin, data)
		return replaceChild(folder, idx, newFile), newFile, nil
	}

	childName := segments[0]
	child, idx := findChild(folder, childName)
	if child == nil {
		if !opts.MkdirParents {
			return folder, nil, VFSError{Code: ErrNotFoundCode, Path: fullPath, Op: "create_file"}
		}
		newFolder := NewMemFolder(mustJoin(folder.path, childName), Meta{}, folder.origin, nil)
		child = newFolder
		folder = replaceChild(folder, idx, child)
	}

	childFolder, ok := child.(MemFolder)
	if !ok {
		return folder, nil, VFSError{Code: ErrNotFolderCode, Path: fullPath, Op: "create_file"}
	}
	newChild, entry, err := memCreateFileAt(childFolder, segments[1:], fullPath, data, opts)
	if err != nil {
		return folder, nil, err
	}
	folder = replaceChild(folder, idx, newChild)
	return folder, entry, nil
}

func memCreateFolderAt(folder MemFolder, segments []string, fullPath VPath, opts WriteOptions) (Folder, Entry, error) {
	if len(segments) == 1 {
		existing, idx := findChild(folder, segments[0])
		if existing != nil {
			if _, ok := existing.(Folder); ok {
				return folder, existing, nil
			}
			return folder, nil, VFSError{Code: ErrAlreadyExistsCode, Path: fullPath, Op: "create_folder"}
		}
		newFolder := NewMemFolder(fullPath, Meta{}, folder.origin, nil)
		return replaceChild(folder, idx, newFolder), newFolder, nil
	}

	childName := segments[0]
	child, idx := findChild(folder, childName)
	if child == nil {
		if !opts.MkdirParents {
			return folder, nil, VFSError{Code: ErrNotFoundCode, Path: fullPath, Op: "create_folder"}
		}
		newFolder := NewMemFolder(mustJoin(folder.path, childName), Meta{}, folder.origin, nil)
		child = newFolder
		folder = replaceChild(folder, idx, child)
	}
	childFolder, ok := child.(MemFolder)
	if !ok {
		return folder, nil, VFSError{Code: ErrNotFolderCode, Path: fullPath, Op: "create_folder"}
	}
	newChild, entry, err := memCreateFolderAt(childFolder, segments[1:], fullPath, opts)
	if err != nil {
		return folder, nil, err
	}
	folder = replaceChild(folder, idx, newChild)
	return folder, entry, nil
}

func memDeleteAt(folder MemFolder, segments []string, fullPath VPath) (MemFolder, Entry, error) {
	child, idx := findChild(folder, segments[0])
	if child == nil {
		return folder, nil, VFSError{Code: ErrNotFoundCode, Path: fullPath, Op: "delete"}
	}

	if len(segments) == 1 {
		newChildren := removeChild(folder.children, idx)
		return NewMemFolder(folder.path, folder.meta, folder.origin, newChildren), child, nil
	}

	childFolder, ok := child.(MemFolder)
	if !ok {
		return folder, nil, VFSError{Code: ErrNotFolderCode, Path: fullPath, Op: "delete"}
	}
	newChild, deleted, err := memDeleteAt(childFolder, segments[1:], fullPath)
	if err != nil {
		return folder, nil, err
	}
	folder = replaceChild(folder, idx, newChild)
	return folder, deleted, nil
}

func memInsertEntry(root MemFolder, path VPath, entry Entry, opts WriteOptions) (Folder, Entry, error) {
	segments := splitPath(path)
	if len(segments) == 0 {
		return root, nil, VFSError{Code: ErrInvalidPathCode, Path: path, Op: "move"}
	}
	return memInsertAt(root, segments, path, entry, opts)
}

func memInsertAt(folder MemFolder, segments []string, fullPath VPath, entry Entry, opts WriteOptions) (Folder, Entry, error) {
	if len(segments) == 1 {
		existing, idx := findChild(folder, segments[0])
		if existing != nil && !opts.Overwrite {
			return folder, nil, VFSError{Code: ErrAlreadyExistsCode, Path: fullPath, Op: "move"}
		}
		return replaceChild(folder, idx, entry), entry, nil
	}

	childName := segments[0]
	child, idx := findChild(folder, childName)
	if child == nil {
		if !opts.MkdirParents {
			return folder, nil, VFSError{Code: ErrNotFoundCode, Path: fullPath, Op: "move"}
		}
		newFolder := NewMemFolder(mustJoin(folder.path, childName), Meta{}, folder.origin, nil)
		child = newFolder
		folder = replaceChild(folder, idx, child)
	}
	childFolder, ok := child.(MemFolder)
	if !ok {
		return folder, nil, VFSError{Code: ErrNotFolderCode, Path: fullPath, Op: "move"}
	}
	newChild, moved, err := memInsertAt(childFolder, segments[1:], fullPath, entry, opts)
	if err != nil {
		return folder, nil, err
	}
	folder = replaceChild(folder, idx, newChild)
	return folder, moved, nil
}

func splitPath(path VPath) []string {
	raw := strings.TrimPrefix(path.String(), "/")
	if raw == "" {
		return nil
	}
	return strings.Split(raw, "/")
}

func memFindEntry(root MemFolder, path VPath) (Entry, bool) {
	segments := splitPath(path)
	if len(segments) == 0 {
		return root, true
	}

	current := Entry(root)
	for i, segment := range segments {
		folder, ok := current.(MemFolder)
		if !ok {
			return nil, false
		}
		child, _ := findChild(folder, segment)
		if child == nil {
			return nil, false
		}
		if i == len(segments)-1 {
			return child, true
		}
		current = child
	}

	return nil, false
}

func findChild(folder MemFolder, name string) (Entry, int) {
	for i, child := range folder.children {
		if baseName(child.Path()) == name {
			return child, i
		}
	}
	return nil, len(folder.children)
}

func replaceChild(folder MemFolder, idx int, entry Entry) MemFolder {
	children := cloneEntries(folder.children)
	if idx >= len(children) {
		children = append(children, entry)
	} else {
		children[idx] = entry
	}
	return NewMemFolder(folder.path, folder.meta, folder.origin, children)
}

func removeChild(children []Entry, idx int) []Entry {
	if idx < 0 || idx >= len(children) {
		return children
	}
	out := make([]Entry, 0, len(children)-1)
	out = append(out, children[:idx]...)
	out = append(out, children[idx+1:]...)
	return out
}

func rebaseEntry(entry Entry, newPath VPath) Entry {
	switch e := entry.(type) {
	case MemFile:
		return NewMemFile(newPath, e.meta, e.origin, e.data)
	case MemFolder:
		children := make([]Entry, 0, len(e.children))
		for _, child := range e.children {
			childName := baseName(child.Path())
			childPath := mustJoin(newPath, childName)
			children = append(children, rebaseEntry(child, childPath))
		}
		return NewMemFolder(newPath, e.meta, e.origin, children)
	case MemDocument:
		return NewMemDocument(newPath, e.meta, e.origin, e.data, rebaseNode(e.root, newPath))
	case MemNode:
		return rebaseNode(e, newPath)
	case MemArchive:
		var exploded Folder
		if e.exploded != nil {
			exploded = rebaseEntry(e.exploded, newPath).(Folder)
		}
		return NewMemArchive(newPath, e.meta, e.origin, e.data, exploded)
	default:
		return entry
	}
}

func rebaseNode(node Node, newPath VPath) Node {
	n, ok := node.(MemNode)
	if !ok {
		return node
	}
	children := make([]Node, 0, len(n.children))
	for _, child := range n.children {
		childName := baseName(child.Path())
		childPath := mustJoin(newPath, childName)
		children = append(children, rebaseNode(child, childPath))
	}
	return NewMemNode(newPath, n.meta, n.origin, n.nodeType, n.attrs, children)
}

func baseName(path VPath) string {
	raw := strings.TrimPrefix(path.String(), "/")
	if raw == "" {
		return ""
	}
	parts := strings.Split(raw, "/")
	return parts[len(parts)-1]
}

func mustJoin(base VPath, name string) VPath {
	path, err := base.Join(name)
	if err != nil {
		panic(err)
	}
	return path
}

func vpathToOSPath(root OSFolder, path VPath) (string, error) {
	rootPath := root.path.String()
	target := path.String()
	if rootPath != "/" && target != rootPath && !strings.HasPrefix(target, rootPath+"/") {
		return "", VFSError{Code: ErrInvalidPathCode, Path: path, Op: "os_path"}
	}
	rel := strings.TrimPrefix(target, rootPath)
	rel = strings.TrimPrefix(rel, "/")
	return filepath.Join(root.osPath, filepath.FromSlash(rel)), nil
}
