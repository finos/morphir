package vfs

type overlayWriter struct {
	vfs    OverlayVFS
	mount  *Mount
	policy WritePolicy
}

func (w *overlayWriter) checkPolicy(req WriteRequest) error {
	if w.policy == nil {
		return nil
	}
	result := w.policy.Evaluate(req)
	if result.Decision == PolicyDeny {
		return VFSError{
			Code:   ErrPolicyDeniedCode,
			Path:   req.Path,
			Op:     string(req.Op),
			Err:    nil,
			Reason: result.Reason,
		}
	}
	return nil
}

func (w *overlayWriter) CreateFile(path VPath, data []byte, opts WriteOptions) (Entry, error) {
	if err := w.checkPolicy(WriteRequest{
		Op:      OpCreateFile,
		Path:    path,
		Mount:   w.mount.Name,
		Options: opts,
	}); err != nil {
		return nil, err
	}

	root := w.mount.Root
	newRoot, entry, err := createFile(root, path, data, opts)
	if err != nil {
		return nil, err
	}
	w.mount.Root = newRoot
	return entry, nil
}

func (w *overlayWriter) CreateFolder(path VPath, opts WriteOptions) (Entry, error) {
	if err := w.checkPolicy(WriteRequest{
		Op:      OpCreateFolder,
		Path:    path,
		Mount:   w.mount.Name,
		Options: opts,
	}); err != nil {
		return nil, err
	}

	root := w.mount.Root
	newRoot, entry, err := createFolder(root, path, opts)
	if err != nil {
		return nil, err
	}
	w.mount.Root = newRoot
	return entry, nil
}

func (w *overlayWriter) UpdateFile(path VPath, data []byte, opts WriteOptions) (Entry, error) {
	if err := w.checkPolicy(WriteRequest{
		Op:      OpUpdateFile,
		Path:    path,
		Mount:   w.mount.Name,
		Options: opts,
	}); err != nil {
		return nil, err
	}

	root := w.mount.Root
	newRoot, entry, err := updateFile(root, path, data, opts)
	if err != nil {
		return nil, err
	}
	w.mount.Root = newRoot
	return entry, nil
}

func (w *overlayWriter) Delete(path VPath) (Entry, error) {
	if err := w.checkPolicy(WriteRequest{
		Op:    OpDelete,
		Path:  path,
		Mount: w.mount.Name,
	}); err != nil {
		return nil, err
	}

	root := w.mount.Root
	newRoot, deleted, err := deleteEntry(root, path)
	if err != nil {
		return nil, err
	}
	w.mount.Root = newRoot
	return deleted, nil
}

func (w *overlayWriter) Move(from VPath, to VPath, opts WriteOptions) (Entry, error) {
	if err := w.checkPolicy(WriteRequest{
		Op:      OpMove,
		Path:    from,
		MoveTo:  &to,
		Mount:   w.mount.Name,
		Options: opts,
	}); err != nil {
		return nil, err
	}

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
	writer  *overlayWriter
	base    Folder
	working Folder
}

func newOverlayTransaction(writer *overlayWriter) *overlayTransaction {
	return &overlayTransaction{
		writer:  writer,
		base:    writer.mount.Root,
		working: writer.mount.Root,
	}
}

func (tx *overlayTransaction) CreateFile(path VPath, data []byte, opts WriteOptions) (Entry, error) {
	if err := tx.writer.checkPolicy(WriteRequest{
		Op:      OpCreateFile,
		Path:    path,
		Mount:   tx.writer.mount.Name,
		Options: opts,
	}); err != nil {
		return nil, err
	}
	return tx.appendOp(func(root Folder) (Folder, Entry, error) {
		return createFile(root, path, data, opts)
	})
}

func (tx *overlayTransaction) CreateFolder(path VPath, opts WriteOptions) (Entry, error) {
	if err := tx.writer.checkPolicy(WriteRequest{
		Op:      OpCreateFolder,
		Path:    path,
		Mount:   tx.writer.mount.Name,
		Options: opts,
	}); err != nil {
		return nil, err
	}
	return tx.appendOp(func(root Folder) (Folder, Entry, error) {
		return createFolder(root, path, opts)
	})
}

func (tx *overlayTransaction) UpdateFile(path VPath, data []byte, opts WriteOptions) (Entry, error) {
	if err := tx.writer.checkPolicy(WriteRequest{
		Op:      OpUpdateFile,
		Path:    path,
		Mount:   tx.writer.mount.Name,
		Options: opts,
	}); err != nil {
		return nil, err
	}
	return tx.appendOp(func(root Folder) (Folder, Entry, error) {
		return updateFile(root, path, data, opts)
	})
}

func (tx *overlayTransaction) Delete(path VPath) (Entry, error) {
	if err := tx.writer.checkPolicy(WriteRequest{
		Op:    OpDelete,
		Path:  path,
		Mount: tx.writer.mount.Name,
	}); err != nil {
		return nil, err
	}
	return tx.appendOp(func(root Folder) (Folder, Entry, error) {
		return deleteEntry(root, path)
	})
}

func (tx *overlayTransaction) Move(from VPath, to VPath, opts WriteOptions) (Entry, error) {
	if err := tx.writer.checkPolicy(WriteRequest{
		Op:      OpMove,
		Path:    from,
		MoveTo:  &to,
		Mount:   tx.writer.mount.Name,
		Options: opts,
	}); err != nil {
		return nil, err
	}
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
