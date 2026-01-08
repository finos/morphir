package vfs

// VFSWalkOptions configures VFS-level traversal behavior.
type VFSWalkOptions struct {
	IncludeShadowed bool
}

// VFSWalkFunc is called for each entry during VFS traversal.
// It receives the entry and whether it's shadowed.
type VFSWalkFunc func(entry Entry, shadowed bool) (WalkControl, error)

// VFSWalk traverses the VFS starting from the given path.
// It resolves the path and walks the entry tree, optionally including shadowed entries.
func VFSWalk(vfs VFS, path VPath, opts VFSWalkOptions, preFn, postFn VFSWalkFunc) error {
	entry, shadowedEntries, err := vfs.Resolve(path)
	if err != nil {
		return err
	}

	// Walk the visible entry
	err = Walk(entry,
		func(e Entry) (WalkControl, error) {
			if preFn != nil {
				return preFn(e, false)
			}
			return WalkContinue, nil
		},
		func(e Entry) (WalkControl, error) {
			if postFn != nil {
				return postFn(e, false)
			}
			return WalkContinue, nil
		},
	)
	if err != nil {
		return err
	}

	// Walk shadowed entries if requested
	if opts.IncludeShadowed {
		for _, sh := range shadowedEntries {
			err = Walk(sh.Entry,
				func(e Entry) (WalkControl, error) {
					if preFn != nil {
						return preFn(e, true)
					}
					return WalkContinue, nil
				},
				func(e Entry) (WalkControl, error) {
					if postFn != nil {
						return postFn(e, true)
					}
					return WalkContinue, nil
				},
			)
			if err != nil {
				return err
			}
		}
	}

	return nil
}

// VFSFilter returns all entries under a path that match the predicate.
func VFSFilter(vfs VFS, path VPath, opts VFSWalkOptions, pred FilterFunc) ([]Entry, error) {
	var results []Entry

	err := VFSWalk(vfs, path, opts,
		func(e Entry, shadowed bool) (WalkControl, error) {
			match, err := pred(e)
			if err != nil {
				return WalkStop, err
			}
			if match {
				results = append(results, e)
			}
			return WalkContinue, nil
		},
		nil,
	)

	if err != nil {
		return nil, err
	}

	return results, nil
}

// VFSMapFunc transforms an entry to a value of type T.
type VFSMapFunc[T any] func(entry Entry, shadowed bool) (T, error)

// VFSMap applies a transformation to all entries under a path.
func VFSMap[T any](vfs VFS, path VPath, opts VFSWalkOptions, mapper VFSMapFunc[T]) ([]T, error) {
	var results []T

	err := VFSWalk(vfs, path, opts,
		func(e Entry, shadowed bool) (WalkControl, error) {
			result, err := mapper(e, shadowed)
			if err != nil {
				return WalkStop, err
			}
			results = append(results, result)
			return WalkContinue, nil
		},
		nil,
	)

	if err != nil {
		return nil, err
	}

	return results, nil
}

// VFSFoldFunc accumulates a result by processing each entry.
type VFSFoldFunc[T any] func(acc T, entry Entry, shadowed bool) (T, error)

// VFSFold reduces entries under a path to a single accumulated value.
func VFSFold[T any](vfs VFS, path VPath, opts VFSWalkOptions, initial T, folder VFSFoldFunc[T]) (T, error) {
	acc := initial

	err := VFSWalk(vfs, path, opts,
		func(e Entry, shadowed bool) (WalkControl, error) {
			var err error
			acc, err = folder(acc, e, shadowed)
			if err != nil {
				return WalkStop, err
			}
			return WalkContinue, nil
		},
		nil,
	)

	if err != nil {
		return acc, err
	}

	return acc, nil
}

// VFSCollect returns all entries under a path as a flat list.
func VFSCollect(vfs VFS, path VPath, opts VFSWalkOptions) ([]Entry, error) {
	var entries []Entry

	err := VFSWalk(vfs, path, opts,
		func(e Entry, shadowed bool) (WalkControl, error) {
			entries = append(entries, e)
			return WalkContinue, nil
		},
		nil,
	)

	if err != nil {
		return nil, err
	}

	return entries, nil
}

// VFSFindByKind returns all entries of a specific kind under a path.
func VFSFindByKind(vfs VFS, path VPath, kind EntryKind, opts VFSWalkOptions) ([]Entry, error) {
	return VFSFilter(vfs, path, opts, func(entry Entry) (bool, error) {
		return entry.Kind() == kind, nil
	})
}

// VFSFindFiles returns all file entries under a path.
func VFSFindFiles(vfs VFS, path VPath, opts VFSWalkOptions) ([]File, error) {
	entries, err := VFSFindByKind(vfs, path, KindFile, opts)
	if err != nil {
		return nil, err
	}

	files := make([]File, 0, len(entries))
	for _, entry := range entries {
		if file, ok := entry.(File); ok {
			files = append(files, file)
		}
	}

	return files, nil
}

// VFSFindFolders returns all folder entries under a path.
func VFSFindFolders(vfs VFS, path VPath, opts VFSWalkOptions) ([]Folder, error) {
	entries, err := VFSFindByKind(vfs, path, KindFolder, opts)
	if err != nil {
		return nil, err
	}

	folders := make([]Folder, 0, len(entries))
	for _, entry := range entries {
		if folder, ok := entry.(Folder); ok {
			folders = append(folders, folder)
		}
	}

	return folders, nil
}

// VFSCountEntries returns the total number of entries under a path.
func VFSCountEntries(vfs VFS, path VPath, opts VFSWalkOptions) (int, error) {
	count := 0

	err := VFSWalk(vfs, path, opts,
		func(e Entry, shadowed bool) (WalkControl, error) {
			count++
			return WalkContinue, nil
		},
		nil,
	)

	if err != nil {
		return 0, err
	}

	return count, nil
}

// VFSWalkGlob traverses entries matching a glob pattern.
// It uses VFS.Find to locate matching entries and walks each one.
func VFSWalkGlob(vfs VFS, pattern Glob, opts VFSWalkOptions, preFn, postFn VFSWalkFunc) error {
	findOpts := FindOptions(opts)

	entries, err := vfs.Find(pattern, findOpts)
	if err != nil {
		return err
	}

	for _, entry := range entries {
		err = Walk(entry,
			func(e Entry) (WalkControl, error) {
				if preFn != nil {
					// Check if this entry is shadowed by looking at its origin
					// This is a simplification; proper shadowing detection would require
					// checking against the VFS resolution
					return preFn(e, false)
				}
				return WalkContinue, nil
			},
			func(e Entry) (WalkControl, error) {
				if postFn != nil {
					return postFn(e, false)
				}
				return WalkContinue, nil
			},
		)
		if err != nil {
			return err
		}
	}

	return nil
}

// VFSCollectGlob returns all entries matching a glob pattern.
func VFSCollectGlob(vfs VFS, pattern Glob, opts VFSWalkOptions) ([]Entry, error) {
	return vfs.Find(pattern, FindOptions(opts))
}
