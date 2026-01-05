package vfs

type overlayWriter struct {
	vfs   OverlayVFS
	mount *Mount
}

func (w *overlayWriter) CreateFile(path VPath, data []byte, opts WriteOptions) (Entry, error) {
	root := w.mount.Root
	newRoot, entry, err := createFile(root, path, data, opts)
	if err != nil {
		return nil, err
	}
	w.mount.Root = newRoot
	return entry, nil
}

func (w *overlayWriter) CreateFolder(path VPath, opts WriteOptions) (Entry, error) {
	root := w.mount.Root
	newRoot, entry, err := createFolder(root, path, opts)
	if err != nil {
		return nil, err
	}
	w.mount.Root = newRoot
	return entry, nil
}

func (w *overlayWriter) UpdateFile(path VPath, data []byte, opts WriteOptions) (Entry, error) {
	root := w.mount.Root
	newRoot, entry, err := updateFile(root, path, data, opts)
	if err != nil {
		return nil, err
	}
	w.mount.Root = newRoot
	return entry, nil
}

func (w *overlayWriter) Delete(path VPath) (Entry, error) {
	root := w.mount.Root
	newRoot, deleted, err := deleteEntry(root, path)
	if err != nil {
		return nil, err
	}
	w.mount.Root = newRoot
	return deleted, nil
}

func (w *overlayWriter) Move(from VPath, to VPath, opts WriteOptions) (Entry, error) {
	root := w.mount.Root
	newRoot, moved, err := moveEntry(root, from, to, opts)
	if err != nil {
		return nil, err
	}
	w.mount.Root = newRoot
	return moved, nil
}

func (w *overlayWriter) Begin() (VFSTransaction, error) {
	return newOverlayTransaction(w), nil
}

type overlayTransaction struct {
	writer *overlayWriter
	base   Folder
	working Folder
}

func newOverlayTransaction(writer *overlayWriter) *overlayTransaction {
	return &overlayTransaction{
		writer: writer,
		base:   writer.mount.Root,
		working: writer.mount.Root,
	}
}

func (tx *overlayTransaction) CreateFile(path VPath, data []byte, opts WriteOptions) (Entry, error) {
	return tx.appendOp(func(root Folder) (Folder, Entry, error) {
		return createFile(root, path, data, opts)
	})
}

func (tx *overlayTransaction) CreateFolder(path VPath, opts WriteOptions) (Entry, error) {
	return tx.appendOp(func(root Folder) (Folder, Entry, error) {
		return createFolder(root, path, opts)
	})
}

func (tx *overlayTransaction) UpdateFile(path VPath, data []byte, opts WriteOptions) (Entry, error) {
	return tx.appendOp(func(root Folder) (Folder, Entry, error) {
		return updateFile(root, path, data, opts)
	})
}

func (tx *overlayTransaction) Delete(path VPath) (Entry, error) {
	return tx.appendOp(func(root Folder) (Folder, Entry, error) {
		return deleteEntry(root, path)
	})
}

func (tx *overlayTransaction) Move(from VPath, to VPath, opts WriteOptions) (Entry, error) {
	return tx.appendOp(func(root Folder) (Folder, Entry, error) {
		return moveEntry(root, from, to, opts)
	})
}

func (tx *overlayTransaction) Commit() error {
	tx.writer.mount.Root = tx.working
	return nil
}

func (tx *overlayTransaction) Rollback() error {
	tx.working = tx.base
	return nil
}

func (tx *overlayTransaction) appendOp(op func(Folder) (Folder, Entry, error)) (Entry, error) {
	newRoot, entry, err := op(tx.working)
	if err != nil {
		return nil, err
	}
	tx.working = newRoot
	return entry, nil
}
