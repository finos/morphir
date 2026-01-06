package domain

// WalkType traverses a type tree depth-first, calling fn for each type.
// If fn returns false, traversal stops for that subtree.
func WalkType(t Type, fn func(Type) bool) {
	if !fn(t) {
		return
	}

	switch typ := t.(type) {
	case ListType:
		WalkType(typ.Element, fn)
	case OptionType:
		WalkType(typ.Inner, fn)
	case ResultType:
		if typ.Ok != nil {
			WalkType(*typ.Ok, fn)
		}
		if typ.Err != nil {
			WalkType(*typ.Err, fn)
		}
	case TupleType:
		for _, elem := range typ.Types {
			WalkType(elem, fn)
		}
	case FutureType:
		if typ.Inner != nil {
			WalkType(*typ.Inner, fn)
		}
	case StreamType:
		if typ.Element != nil {
			WalkType(*typ.Element, fn)
		}
	case PrimitiveType, NamedType, HandleType:
		// Leaf types - no traversal needed
	}
}

// MapType applies a transformation function to all types in a type tree.
// Returns a new type tree with transformations applied.
func MapType(t Type, fn func(Type) Type) Type {
	// Apply transformation to current type first
	t = fn(t)

	// Then recursively map children
	switch typ := t.(type) {
	case ListType:
		return ListType{Element: MapType(typ.Element, fn)}

	case OptionType:
		return OptionType{Inner: MapType(typ.Inner, fn)}

	case ResultType:
		result := ResultType{}
		if typ.Ok != nil {
			mapped := MapType(*typ.Ok, fn)
			result.Ok = &mapped
		}
		if typ.Err != nil {
			mapped := MapType(*typ.Err, fn)
			result.Err = &mapped
		}
		return result

	case TupleType:
		newTypes := make([]Type, len(typ.Types))
		for i, elem := range typ.Types {
			newTypes[i] = MapType(elem, fn)
		}
		return TupleType{Types: newTypes}

	case FutureType:
		future := FutureType{}
		if typ.Inner != nil {
			mapped := MapType(*typ.Inner, fn)
			future.Inner = &mapped
		}
		return future

	case StreamType:
		stream := StreamType{}
		if typ.Element != nil {
			mapped := MapType(*typ.Element, fn)
			stream.Element = &mapped
		}
		return stream

	default:
		// Leaf types (PrimitiveType, NamedType, HandleType)
		return t
	}
}

// FoldType performs a left fold over a type tree, accumulating a result.
func FoldType[R any](t Type, init R, fn func(R, Type) R) R {
	acc := fn(init, t)

	switch typ := t.(type) {
	case ListType:
		return FoldType(typ.Element, acc, fn)

	case OptionType:
		return FoldType(typ.Inner, acc, fn)

	case ResultType:
		if typ.Ok != nil {
			acc = FoldType(*typ.Ok, acc, fn)
		}
		if typ.Err != nil {
			acc = FoldType(*typ.Err, acc, fn)
		}
		return acc

	case TupleType:
		for _, elem := range typ.Types {
			acc = FoldType(elem, acc, fn)
		}
		return acc

	case FutureType:
		if typ.Inner != nil {
			return FoldType(*typ.Inner, acc, fn)
		}
		return acc

	case StreamType:
		if typ.Element != nil {
			return FoldType(*typ.Element, acc, fn)
		}
		return acc

	default:
		// Leaf types
		return acc
	}
}

// CollectTypes collects all types matching a predicate from a type tree.
func CollectTypes(t Type, pred func(Type) bool) []Type {
	var collected []Type
	WalkType(t, func(typ Type) bool {
		if pred(typ) {
			collected = append(collected, typ)
		}
		return true
	})
	return collected
}

// ContainsType checks if a type tree contains a type matching the predicate.
func ContainsType(t Type, pred func(Type) bool) bool {
	found := false
	WalkType(t, func(typ Type) bool {
		if pred(typ) {
			found = true
			return false // stop traversal
		}
		return true
	})
	return found
}

// TypeDepth returns the maximum nesting depth of a type tree.
func TypeDepth(t Type) int {
	return FoldType(t, 0, func(maxDepth int, typ Type) int {
		depth := 1
		switch t := typ.(type) {
		case ListType:
			depth += TypeDepth(t.Element)
		case OptionType:
			depth += TypeDepth(t.Inner)
		case ResultType:
			okDepth := 0
			if t.Ok != nil {
				okDepth = TypeDepth(*t.Ok)
			}
			errDepth := 0
			if t.Err != nil {
				errDepth = TypeDepth(*t.Err)
			}
			if okDepth > errDepth {
				depth += okDepth
			} else {
				depth += errDepth
			}
		case TupleType:
			for _, elem := range t.Types {
				elemDepth := TypeDepth(elem)
				if elemDepth > depth-1 {
					depth = elemDepth + 1
				}
			}
		}

		if depth > maxDepth {
			return depth
		}
		return maxDepth
	})
}
