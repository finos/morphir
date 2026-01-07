package vfs

import "github.com/bmatcuk/doublestar/v4"

// OverlayVFS provides a mount-based virtual filesystem with precedence.
// Mounts are ordered from lowest to highest precedence.
type OverlayVFS struct {
	mounts []Mount
}

// NewOverlayVFS constructs an OverlayVFS with the provided mounts.
func NewOverlayVFS(mounts []Mount) OverlayVFS {
	copied := make([]Mount, len(mounts))
	copy(copied, mounts)
	return OverlayVFS{mounts: copied}
}

// Writer returns a writer that targets the highest-precedence RW mount.
func (vfs OverlayVFS) Writer() (VFSWriter, error) {
	for i := len(vfs.mounts) - 1; i >= 0; i-- {
		if vfs.mounts[i].Mode == MountRW {
			return &overlayWriter{vfs: vfs, mount: &vfs.mounts[i], policy: nil}, nil
		}
	}
	return nil, VFSError{Code: ErrReadOnlyMountCode, Op: "writer"}
}

// WriterForMount returns a writer scoped to a specific mount.
func (vfs OverlayVFS) WriterForMount(name string) (VFSWriter, error) {
	for i := range vfs.mounts {
		if vfs.mounts[i].Name == name {
			if vfs.mounts[i].Mode != MountRW {
				return nil, VFSError{Code: ErrReadOnlyMountCode, Mount: name, Op: "writer_for_mount"}
			}
			return &overlayWriter{vfs: vfs, mount: &vfs.mounts[i], policy: nil}, nil
		}
	}
	return nil, VFSError{Code: ErrMountNotFoundCode, Mount: name, Op: "writer_for_mount"}
}

// WriterWithPolicy returns a writer with a custom write policy.
func (vfs OverlayVFS) WriterWithPolicy(policy WritePolicy) (VFSWriter, error) {
	for i := len(vfs.mounts) - 1; i >= 0; i-- {
		if vfs.mounts[i].Mode == MountRW {
			return &overlayWriter{vfs: vfs, mount: &vfs.mounts[i], policy: policy}, nil
		}
	}
	return nil, VFSError{Code: ErrReadOnlyMountCode, Op: "writer_with_policy"}
}

// WriterForMountWithPolicy returns a writer scoped to a specific mount with a custom policy.
func (vfs OverlayVFS) WriterForMountWithPolicy(name string, policy WritePolicy) (VFSWriter, error) {
	for i := range vfs.mounts {
		if vfs.mounts[i].Name == name {
			if vfs.mounts[i].Mode != MountRW {
				return nil, VFSError{Code: ErrReadOnlyMountCode, Mount: name, Op: "writer_for_mount_with_policy"}
			}
			return &overlayWriter{vfs: vfs, mount: &vfs.mounts[i], policy: policy}, nil
		}
	}
	return nil, VFSError{Code: ErrMountNotFoundCode, Mount: name, Op: "writer_for_mount_with_policy"}
}

// Resolve returns the visible entry at a path and its shadowed lineage.
func (vfs OverlayVFS) Resolve(path VPath) (Entry, []ShadowedEntry, error) {
	var visible Entry
	var visibleMountName string
	var shadowed []ShadowedEntry

	for i := len(vfs.mounts) - 1; i >= 0; i-- {
		entry, ok, err := findEntryInMount(vfs.mounts[i], path)
		if err != nil {
			return nil, nil, err
		}
		if !ok {
			continue
		}
		if visible == nil {
			visible = entry
			visibleMountName = vfs.mounts[i].Name
			continue
		}
		shadowed = append(shadowed, ShadowedEntry{
			Entry:       entry,
			Mount:       vfs.mounts[i],
			Reason:      "overridden by higher-precedence mount",
			ShadowedBy:  visibleMountName,
			VisiblePath: visible.Path(),
		})
	}

	if visible == nil {
		return nil, nil, VFSError{Code: ErrNotFoundCode, Path: path, Op: "resolve"}
	}

	return visible, shadowed, nil
}

// List returns the entries in a folder path. Shadowed entries are optional.
func (vfs OverlayVFS) List(path VPath, opts ListOptions) ([]Entry, error) {
	var out []Entry
	seen := make(map[string]struct{})

	for i := len(vfs.mounts) - 1; i >= 0; i-- {
		children, ok, err := listChildrenInMount(vfs.mounts[i], path)
		if err != nil {
			return nil, err
		}
		if !ok {
			continue
		}
		for _, child := range children {
			key := child.Path().String()
			if _, exists := seen[key]; exists {
				if opts.IncludeShadowed {
					out = append(out, child)
				}
				continue
			}
			seen[key] = struct{}{}
			out = append(out, child)
		}
	}

	return out, nil
}

// Find returns entries whose paths match the glob pattern.
func (vfs OverlayVFS) Find(glob Glob, opts FindOptions) ([]Entry, error) {
	var out []Entry
	seen := make(map[string]struct{})

	for i := len(vfs.mounts) - 1; i >= 0; i-- {
		err := walkMount(vfs.mounts[i], func(entry Entry) error {
			matched, err := doublestar.Match(glob.String(), entry.Path().String())
			if err != nil {
				return err
			}
			if !matched {
				return nil
			}

			key := entry.Path().String()
			if _, exists := seen[key]; exists {
				if opts.IncludeShadowed {
					out = append(out, entry)
				}
				return nil
			}
			seen[key] = struct{}{}
			out = append(out, entry)
			return nil
		})
		if err != nil {
			return nil, err
		}
	}

	return out, nil
}

func findEntryInMount(mount Mount, path VPath) (Entry, bool, error) {
	return findEntry(mount.Root, path)
}

func findEntry(entry Entry, path VPath) (Entry, bool, error) {
	if entry.Path().String() == path.String() {
		return entry, true, nil
	}

	folder, ok := entry.(Folder)
	if !ok {
		return nil, false, nil
	}

	children, err := folder.Children()
	if err != nil {
		return nil, false, err
	}
	for _, child := range children {
		found, ok, err := findEntry(child, path)
		if err != nil || ok {
			return found, ok, err
		}
	}

	return nil, false, nil
}

func listChildrenInMount(mount Mount, path VPath) ([]Entry, bool, error) {
	entry, ok, err := findEntryInMount(mount, path)
	if err != nil || !ok {
		return nil, ok, err
	}

	folder, ok := entry.(Folder)
	if !ok {
		return nil, false, nil
	}

	children, err := folder.Children()
	if err != nil {
		return nil, false, err
	}
	return children, true, nil
}

func walkMount(mount Mount, fn func(Entry) error) error {
	return walkEntry(mount.Root, fn)
}

func walkEntry(entry Entry, fn func(Entry) error) error {
	if err := fn(entry); err != nil {
		return err
	}

	folder, ok := entry.(Folder)
	if !ok {
		return nil
	}

	children, err := folder.Children()
	if err != nil {
		return err
	}
	for _, child := range children {
		if err := walkEntry(child, fn); err != nil {
			return err
		}
	}

	return nil
}
