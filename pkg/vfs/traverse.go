package vfs

import "errors"

// WalkControl indicates how to proceed during traversal.
type WalkControl int

const (
	WalkContinue WalkControl = iota // Continue traversal normally
	WalkSkip                        // Skip children of current entry
	WalkStop                        // Stop traversal immediately
)

// WalkFunc is called for each entry during traversal.
// Return WalkContinue to proceed, WalkSkip to skip children, or WalkStop to halt.
type WalkFunc func(entry Entry) (WalkControl, error)

// errWalkStop is an internal sentinel error used to propagate WalkStop through recursion.
var errWalkStop = errors.New("walk stopped")

// Walk traverses an entry tree with pre-order and post-order callbacks.
// Both preFn and postFn are optional (can be nil).
// preFn is called before visiting children, postFn is called after.
// If preFn returns WalkSkip, children are skipped and postFn is still called.
// If either function returns WalkStop, traversal halts immediately.
func Walk(entry Entry, preFn, postFn WalkFunc) error {
	err := walk(entry, preFn, postFn)
	if errors.Is(err, errWalkStop) {
		return nil
	}
	return err
}

func walk(entry Entry, preFn, postFn WalkFunc) error {
	// Pre-order callback
	skipChildren := false
	if preFn != nil {
		ctrl, err := preFn(entry)
		if err != nil {
			return err
		}
		switch ctrl {
		case WalkStop:
			return errWalkStop
		case WalkSkip:
			skipChildren = true
		}
	}

	// Visit children if not skipped
	if !skipChildren {
		folder, ok := entry.(Folder)
		if ok {
			children, err := folder.Children()
			if err != nil {
				return err
			}
			for _, child := range children {
				if err := walk(child, preFn, postFn); err != nil {
					return err
				}
			}
		}
	}

	// Post-order callback
	if postFn != nil {
		ctrl, err := postFn(entry)
		if err != nil {
			return err
		}
		if ctrl == WalkStop {
			return errWalkStop
		}
	}

	return nil
}

// FilterFunc is a predicate function for filtering entries.
type FilterFunc func(entry Entry) (bool, error)

// Filter returns all entries in the tree that match the predicate.
// Traversal continues even if a parent doesn't match (children may still match).
func Filter(entry Entry, pred FilterFunc) ([]Entry, error) {
	var results []Entry
	err := Walk(entry, func(e Entry) (WalkControl, error) {
		match, err := pred(e)
		if err != nil {
			return WalkStop, err
		}
		if match {
			results = append(results, e)
		}
		return WalkContinue, nil
	}, nil)
	if err != nil {
		return nil, err
	}
	return results, nil
}

// MapSameFunc transforms an entry to another entry of the same kind.
type MapSameFunc func(entry Entry) (Entry, error)

// MapSame recursively transforms entries using the provided function.
// The function must return an entry of the same kind as the input.
// For folders, children are recursively mapped before calling the function.
func MapSame(entry Entry, fn MapSameFunc) (Entry, error) {
	// For folders, recursively map children first
	if folder, ok := entry.(Folder); ok {
		children, err := folder.Children()
		if err != nil {
			return nil, err
		}

		mappedChildren := make([]Entry, len(children))
		for i, child := range children {
			mapped, err := MapSame(child, fn)
			if err != nil {
				return nil, err
			}
			mappedChildren[i] = mapped
		}

		// Create a new folder with mapped children
		// For MemFolder, we can reconstruct it
		if memFolder, ok := folder.(MemFolder); ok {
			transformed := NewMemFolder(
				memFolder.Path(),
				memFolder.Meta(),
				memFolder.Origin(),
				mappedChildren,
			)
			return fn(transformed)
		}

		// For other folder types, we can't easily reconstruct them
		// So we just call the function on the original
		return fn(entry)
	}

	// For non-folders, just apply the function
	return fn(entry)
}

// MapFunc transforms an entry to a different entry (possibly different kind).
type MapFunc func(entry Entry) (Entry, error)

// Map recursively transforms entries using the provided function.
// Unlike MapSame, the function can return entries of different kinds.
// For folders, children are recursively mapped before calling the function.
// If the function transforms a folder to a non-folder, children are not preserved.
func Map(entry Entry, fn MapFunc) (Entry, error) {
	// For folders, recursively map children first
	if folder, ok := entry.(Folder); ok {
		children, err := folder.Children()
		if err != nil {
			return nil, err
		}

		mappedChildren := make([]Entry, len(children))
		for i, child := range children {
			mapped, err := Map(child, fn)
			if err != nil {
				return nil, err
			}
			mappedChildren[i] = mapped
		}

		// Create a new folder with mapped children
		if memFolder, ok := folder.(MemFolder); ok {
			withChildren := NewMemFolder(
				memFolder.Path(),
				memFolder.Meta(),
				memFolder.Origin(),
				mappedChildren,
			)
			return fn(withChildren)
		}

		// For other folder types, try to apply the function
		return fn(entry)
	}

	// For non-folders, just apply the function
	return fn(entry)
}

// FoldFunc accumulates a result by processing each entry.
type FoldFunc[T any] func(acc T, entry Entry) (T, error)

// Fold performs a pre-order traversal, accumulating a result.
// The accumulator is threaded through the traversal in pre-order.
func Fold[T any](entry Entry, initial T, fn FoldFunc[T]) (T, error) {
	acc := initial
	err := Walk(entry, func(e Entry) (WalkControl, error) {
		var err error
		acc, err = fn(acc, e)
		if err != nil {
			return WalkStop, err
		}
		return WalkContinue, nil
	}, nil)
	if err != nil {
		return acc, err
	}
	return acc, nil
}
