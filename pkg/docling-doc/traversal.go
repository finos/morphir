package docling

// Visitor is a function that processes an item during traversal.
// It returns an error if processing should stop.
type Visitor func(item Item) error

// Walk performs a depth-first traversal of the document tree starting from the given reference.
// It applies the visitor function to each item encountered.
func Walk(doc DoclingDocument, startRef Ref, visitor Visitor) error {
	item := doc.GetItem(startRef)
	if item == nil {
		return nil
	}

	// Visit the current item
	if err := visitor(item); err != nil {
		return err
	}

	// Recursively visit children
	for _, childRef := range item.Children() {
		if err := Walk(doc, childRef, visitor); err != nil {
			return err
		}
	}

	return nil
}

// WalkBody performs a depth-first traversal of the document body.
func WalkBody(doc DoclingDocument, visitor Visitor) error {
	if doc.Body() == nil {
		return nil
	}
	return Walk(doc, *doc.Body(), visitor)
}

// WalkAll applies the visitor to all items in the document.
// The order is undefined (uses map iteration).
func WalkAll(doc DoclingDocument, visitor Visitor) error {
	for _, item := range doc.Items() {
		if err := visitor(item); err != nil {
			return err
		}
	}
	return nil
}

// Filter returns a new document containing only items that satisfy the predicate.
func Filter(doc DoclingDocument, predicate func(Item) bool) DoclingDocument {
	newDoc := NewDocument(doc.Name())
	newDoc = newDoc.WithMetadata("filtered", true)

	for ref, item := range doc.Items() {
		if predicate(item) {
			newDoc = newDoc.WithItem(item)
		} else if doc.Body() != nil && *doc.Body() == ref {
			// Clear body ref if the body item is filtered out
			newDoc.body = nil
		}
	}

	// Preserve pages
	for _, page := range doc.Pages() {
		newDoc = newDoc.WithPage(page)
	}

	return newDoc
}

// FilterByLabel returns a new document containing only items with the specified label.
func FilterByLabel(doc DoclingDocument, label ItemLabel) DoclingDocument {
	return Filter(doc, func(item Item) bool {
		return item.Label() == label
	})
}

// Map applies a transformation function to each item in the document.
// The function should return a new item or nil to exclude the item.
func Map(doc DoclingDocument, transform func(Item) Item) DoclingDocument {
	newDoc := NewDocument(doc.Name())

	for _, item := range doc.Items() {
		newItem := transform(item)
		if newItem != nil {
			newDoc = newDoc.WithItem(newItem)
		}
	}

	// Preserve body reference if it still exists
	if doc.Body() != nil && newDoc.HasItem(*doc.Body()) {
		newDoc = newDoc.WithBody(*doc.Body())
	}

	// Preserve pages
	for _, page := range doc.Pages() {
		newDoc = newDoc.WithPage(page)
	}

	return newDoc
}

// Fold performs a left fold over all items in the document.
// The order is undefined (uses map iteration).
func Fold[T any](doc DoclingDocument, initial T, fn func(T, Item) T) T {
	result := initial
	for _, item := range doc.Items() {
		result = fn(result, item)
	}
	return result
}

// Collect gathers items that satisfy the predicate into a slice.
func Collect(doc DoclingDocument, predicate func(Item) bool) []Item {
	var result []Item
	for _, item := range doc.Items() {
		if predicate(item) {
			result = append(result, item)
		}
	}
	return result
}

// CollectByLabel gathers all items with the specified label.
func CollectByLabel(doc DoclingDocument, label ItemLabel) []Item {
	return Collect(doc, func(item Item) bool {
		return item.Label() == label
	})
}

// Find returns the first item that satisfies the predicate, or nil if not found.
func Find(doc DoclingDocument, predicate func(Item) bool) Item {
	for _, item := range doc.Items() {
		if predicate(item) {
			return item
		}
	}
	return nil
}

// FindByLabel returns the first item with the specified label, or nil if not found.
func FindByLabel(doc DoclingDocument, label ItemLabel) Item {
	return Find(doc, func(item Item) bool {
		return item.Label() == label
	})
}

// Any checks if any item satisfies the predicate.
func Any(doc DoclingDocument, predicate func(Item) bool) bool {
	for _, item := range doc.Items() {
		if predicate(item) {
			return true
		}
	}
	return false
}

// All checks if all items satisfy the predicate.
func All(doc DoclingDocument, predicate func(Item) bool) bool {
	for _, item := range doc.Items() {
		if !predicate(item) {
			return false
		}
	}
	return true
}

// Count returns the number of items that satisfy the predicate.
func Count(doc DoclingDocument, predicate func(Item) bool) int {
	count := 0
	for _, item := range doc.Items() {
		if predicate(item) {
			count++
		}
	}
	return count
}

// CountByLabel returns the number of items with the specified label.
func CountByLabel(doc DoclingDocument, label ItemLabel) int {
	return Count(doc, func(item Item) bool {
		return item.Label() == label
	})
}

// IterateTree performs an in-order traversal of the tree starting from the given reference,
// yielding items to a channel for push-based processing.
func IterateTree(doc DoclingDocument, startRef Ref) <-chan Item {
	ch := make(chan Item)
	go func() {
		defer close(ch)
		var traverse func(Ref)
		traverse = func(ref Ref) {
			item := doc.GetItem(ref)
			if item == nil {
				return
			}
			ch <- item
			for _, childRef := range item.Children() {
				traverse(childRef)
			}
		}
		traverse(startRef)
	}()
	return ch
}

// IterateBody performs an in-order traversal of the document body,
// yielding items to a channel for push-based processing.
func IterateBody(doc DoclingDocument) <-chan Item {
	if doc.Body() == nil {
		ch := make(chan Item)
		close(ch)
		return ch
	}
	return IterateTree(doc, *doc.Body())
}
