package ir

// Visitor Framework for Morphir IR Trees
//
// This file provides a visitor pattern implementation for traversing Morphir IR
// trees (Type, Pattern, and in future Value). The visitor pattern allows you to
// define custom operations that can traverse IR trees without modifying the
// tree types themselves.
//
// # Key Concepts
//
// The visitor framework consists of:
//   - TraversalAction: Controls how traversal proceeds (Continue, SkipChildren, Stop)
//   - Visitor interfaces: Define Enter/Exit callbacks for each node type
//   - Base visitors: Provide default no-op implementations
//   - Walk functions: Traverse trees using a visitor
//
// # When to Use Visitors vs Fold/Map
//
// Use Visitors when you need:
//   - Pre-order and post-order hooks at the same time
//   - Fine-grained control over traversal (skip subtrees, early termination)
//   - To maintain complex state during traversal
//   - To implement operations that don't return a value per node
//
// Use Fold (TypeFold) when you need:
//   - Bottom-up computation where each node combines child results
//   - Simple transformations that produce a single result
//   - Catamorphism-style operations
//
// Use Map (MapType) when you need:
//   - To transform the tree while preserving structure
//   - Bottom-up rewriting
//
// # Usage Example: Counting Type Variables
//
//	type countingVisitor struct {
//	    ir.BaseTypeVisitor[int, int] // Embed base for default no-ops
//	}
//
//	func (v countingVisitor) EnterTypeVariable(count int, t ir.TypeVariable[int]) (int, ir.TraversalAction) {
//	    return count + 1, ir.Continue
//	}
//
//	func countTypeVariables(t ir.Type[int]) int {
//	    count, _ := ir.WalkType(t, countingVisitor{}, 0)
//	    return count
//	}
//
// # Usage Example: Collecting All Type Variable Names
//
//	type nameCollector struct {
//	    ir.BaseTypeVisitor[int, []string]
//	}
//
//	func (v nameCollector) EnterTypeVariable(names []string, t ir.TypeVariable[int]) ([]string, ir.TraversalAction) {
//	    return append(names, t.Name().ToTitleCase()), ir.Continue
//	}
//
//	func collectNames(t ir.Type[int]) []string {
//	    names, _ := ir.WalkType(t, nameCollector{}, []string{})
//	    return names
//	}
//
// # Usage Example: Early Termination (Find First)
//
//	type finder struct {
//	    ir.BaseTypeVisitor[int, *ir.TypeVariable[int]]
//	    targetName string
//	}
//
//	func (v finder) EnterTypeVariable(result *ir.TypeVariable[int], t ir.TypeVariable[int]) (*ir.TypeVariable[int], ir.TraversalAction) {
//	    if t.Name().ToTitleCase() == v.targetName {
//	        return &t, ir.Stop // Found it, stop traversal
//	    }
//	    return result, ir.Continue
//	}
//
//	func findTypeVariable(t ir.Type[int], name string) *ir.TypeVariable[int] {
//	    result, _ := ir.WalkType(t, finder{targetName: name}, nil)
//	    return result
//	}
//
// # Usage Example: Skipping Subtrees
//
//	type shallowCounter struct {
//	    ir.BaseTypeVisitor[int, int]
//	}
//
//	func (v shallowCounter) EnterType(count int, t ir.Type[int]) (int, ir.TraversalAction) {
//	    return count + 1, ir.Continue
//	}
//
//	func (v shallowCounter) EnterTypeReference(count int, t ir.TypeReference[int]) (int, ir.TraversalAction) {
//	    // Don't recurse into type parameters
//	    return count, ir.SkipChildren
//	}
//
// # Thread Safety
//
// The visitor framework is not inherently thread-safe. If you need to traverse
// the same tree concurrently, use separate visitor instances or synchronize
// access to shared state.
//
// # Extending the Framework
//
// To add visitor support for new IR types (like Value), follow the pattern:
// 1. Define a Visitor interface with Enter/Exit methods for each variant
// 2. Create a Base visitor with default no-op implementations
// 3. Implement a Walk function that dispatches to the correct handlers

// TraversalAction controls the behavior of tree traversal.
type TraversalAction int

const (
	// Continue proceeds with normal traversal (visit children).
	Continue TraversalAction = iota
	// SkipChildren skips visiting children of the current node.
	SkipChildren
	// Stop aborts the entire traversal.
	Stop
)

// TypeVisitor defines callbacks for visiting Type nodes.
//
// The visitor pattern provides pre-order (Enter) and post-order (Exit) hooks
// for each node type. Enter is called before visiting children, Exit after.
//
// Enter methods return a TraversalAction to control traversal:
//   - Continue: visit children normally
//   - SkipChildren: skip children but continue with siblings
//   - Stop: abort the entire traversal
//
// Exit methods are only called if Enter returned Continue and children were visited.
// They are not called if Enter returned SkipChildren or Stop.
//
// The state parameter S allows threading context through the traversal.
type TypeVisitor[A any, S any] interface {
	// EnterType is called before dispatching to specific type handlers.
	// This provides a hook for visiting any type node.
	EnterType(state S, t Type[A]) (S, TraversalAction)
	// ExitType is called after visiting a type node and its children.
	ExitType(state S, t Type[A]) S

	// Type-specific enter handlers
	EnterTypeVariable(state S, t TypeVariable[A]) (S, TraversalAction)
	EnterTypeReference(state S, t TypeReference[A]) (S, TraversalAction)
	EnterTypeTuple(state S, t TypeTuple[A]) (S, TraversalAction)
	EnterTypeRecord(state S, t TypeRecord[A]) (S, TraversalAction)
	EnterTypeExtensibleRecord(state S, t TypeExtensibleRecord[A]) (S, TraversalAction)
	EnterTypeFunction(state S, t TypeFunction[A]) (S, TraversalAction)
	EnterTypeUnit(state S, t TypeUnit[A]) (S, TraversalAction)

	// Type-specific exit handlers
	ExitTypeVariable(state S, t TypeVariable[A]) S
	ExitTypeReference(state S, t TypeReference[A]) S
	ExitTypeTuple(state S, t TypeTuple[A]) S
	ExitTypeRecord(state S, t TypeRecord[A]) S
	ExitTypeExtensibleRecord(state S, t TypeExtensibleRecord[A]) S
	ExitTypeFunction(state S, t TypeFunction[A]) S
	ExitTypeUnit(state S, t TypeUnit[A]) S
}

// BaseTypeVisitor provides default no-op implementations for TypeVisitor.
// Embed this in your visitor to only override the methods you need.
type BaseTypeVisitor[A any, S any] struct{}

func (BaseTypeVisitor[A, S]) EnterType(state S, t Type[A]) (S, TraversalAction) {
	return state, Continue
}
func (BaseTypeVisitor[A, S]) ExitType(state S, t Type[A]) S { return state }

func (BaseTypeVisitor[A, S]) EnterTypeVariable(state S, t TypeVariable[A]) (S, TraversalAction) {
	return state, Continue
}
func (BaseTypeVisitor[A, S]) EnterTypeReference(state S, t TypeReference[A]) (S, TraversalAction) {
	return state, Continue
}
func (BaseTypeVisitor[A, S]) EnterTypeTuple(state S, t TypeTuple[A]) (S, TraversalAction) {
	return state, Continue
}
func (BaseTypeVisitor[A, S]) EnterTypeRecord(state S, t TypeRecord[A]) (S, TraversalAction) {
	return state, Continue
}
func (BaseTypeVisitor[A, S]) EnterTypeExtensibleRecord(state S, t TypeExtensibleRecord[A]) (S, TraversalAction) {
	return state, Continue
}
func (BaseTypeVisitor[A, S]) EnterTypeFunction(state S, t TypeFunction[A]) (S, TraversalAction) {
	return state, Continue
}
func (BaseTypeVisitor[A, S]) EnterTypeUnit(state S, t TypeUnit[A]) (S, TraversalAction) {
	return state, Continue
}

func (BaseTypeVisitor[A, S]) ExitTypeVariable(state S, t TypeVariable[A]) S         { return state }
func (BaseTypeVisitor[A, S]) ExitTypeReference(state S, t TypeReference[A]) S       { return state }
func (BaseTypeVisitor[A, S]) ExitTypeTuple(state S, t TypeTuple[A]) S               { return state }
func (BaseTypeVisitor[A, S]) ExitTypeRecord(state S, t TypeRecord[A]) S             { return state }
func (BaseTypeVisitor[A, S]) ExitTypeExtensibleRecord(state S, t TypeExtensibleRecord[A]) S { return state }
func (BaseTypeVisitor[A, S]) ExitTypeFunction(state S, t TypeFunction[A]) S         { return state }
func (BaseTypeVisitor[A, S]) ExitTypeUnit(state S, t TypeUnit[A]) S                 { return state }

// WalkType traverses a Type tree using the provided visitor.
// Returns the final state and whether traversal completed (true) or was stopped (false).
func WalkType[A any, S any](t Type[A], visitor TypeVisitor[A, S], state S) (S, bool) {
	if t == nil {
		return state, true
	}

	// Call generic enter hook
	state, action := visitor.EnterType(state, t)
	if action == Stop {
		return state, false
	}
	if action == SkipChildren {
		return state, true
	}

	// Dispatch to specific type and walk children
	var completed bool
	switch v := t.(type) {
	case TypeVariable[A]:
		state, completed = walkTypeVariable(v, visitor, state)
	case TypeReference[A]:
		state, completed = walkTypeReference(v, visitor, state)
	case TypeTuple[A]:
		state, completed = walkTypeTuple(v, visitor, state)
	case TypeRecord[A]:
		state, completed = walkTypeRecord(v, visitor, state)
	case TypeExtensibleRecord[A]:
		state, completed = walkTypeExtensibleRecord(v, visitor, state)
	case TypeFunction[A]:
		state, completed = walkTypeFunction(v, visitor, state)
	case TypeUnit[A]:
		state, completed = walkTypeUnit(v, visitor, state)
	default:
		// Unknown type, just return
		return state, true
	}

	if !completed {
		return state, false
	}

	// Call generic exit hook
	state = visitor.ExitType(state, t)
	return state, true
}

func walkTypeVariable[A any, S any](t TypeVariable[A], v TypeVisitor[A, S], state S) (S, bool) {
	state, action := v.EnterTypeVariable(state, t)
	if action == Stop {
		return state, false
	}
	// TypeVariable has no children
	if action != SkipChildren {
		state = v.ExitTypeVariable(state, t)
	}
	return state, true
}

func walkTypeReference[A any, S any](t TypeReference[A], v TypeVisitor[A, S], state S) (S, bool) {
	state, action := v.EnterTypeReference(state, t)
	if action == Stop {
		return state, false
	}
	if action == SkipChildren {
		return state, true
	}

	// Walk type parameters
	for _, param := range t.typeParams {
		var completed bool
		state, completed = WalkType(param, v, state)
		if !completed {
			return state, false
		}
	}

	state = v.ExitTypeReference(state, t)
	return state, true
}

func walkTypeTuple[A any, S any](t TypeTuple[A], v TypeVisitor[A, S], state S) (S, bool) {
	state, action := v.EnterTypeTuple(state, t)
	if action == Stop {
		return state, false
	}
	if action == SkipChildren {
		return state, true
	}

	// Walk elements
	for _, elem := range t.elements {
		var completed bool
		state, completed = WalkType(elem, v, state)
		if !completed {
			return state, false
		}
	}

	state = v.ExitTypeTuple(state, t)
	return state, true
}

func walkTypeRecord[A any, S any](t TypeRecord[A], v TypeVisitor[A, S], state S) (S, bool) {
	state, action := v.EnterTypeRecord(state, t)
	if action == Stop {
		return state, false
	}
	if action == SkipChildren {
		return state, true
	}

	// Walk field types
	for _, field := range t.fields {
		var completed bool
		state, completed = WalkType(field.tpe, v, state)
		if !completed {
			return state, false
		}
	}

	state = v.ExitTypeRecord(state, t)
	return state, true
}

func walkTypeExtensibleRecord[A any, S any](t TypeExtensibleRecord[A], v TypeVisitor[A, S], state S) (S, bool) {
	state, action := v.EnterTypeExtensibleRecord(state, t)
	if action == Stop {
		return state, false
	}
	if action == SkipChildren {
		return state, true
	}

	// Walk field types
	for _, field := range t.fields {
		var completed bool
		state, completed = WalkType(field.tpe, v, state)
		if !completed {
			return state, false
		}
	}

	state = v.ExitTypeExtensibleRecord(state, t)
	return state, true
}

func walkTypeFunction[A any, S any](t TypeFunction[A], v TypeVisitor[A, S], state S) (S, bool) {
	state, action := v.EnterTypeFunction(state, t)
	if action == Stop {
		return state, false
	}
	if action == SkipChildren {
		return state, true
	}

	// Walk argument type
	var completed bool
	state, completed = WalkType(t.argument, v, state)
	if !completed {
		return state, false
	}

	// Walk result type
	state, completed = WalkType(t.result, v, state)
	if !completed {
		return state, false
	}

	state = v.ExitTypeFunction(state, t)
	return state, true
}

func walkTypeUnit[A any, S any](t TypeUnit[A], v TypeVisitor[A, S], state S) (S, bool) {
	state, action := v.EnterTypeUnit(state, t)
	if action == Stop {
		return state, false
	}
	// TypeUnit has no children
	if action != SkipChildren {
		state = v.ExitTypeUnit(state, t)
	}
	return state, true
}

// PatternVisitor defines callbacks for visiting Pattern nodes.
type PatternVisitor[A any, S any] interface {
	EnterPattern(state S, p Pattern[A]) (S, TraversalAction)
	ExitPattern(state S, p Pattern[A]) S

	EnterWildcardPattern(state S, p WildcardPattern[A]) (S, TraversalAction)
	EnterAsPattern(state S, p AsPattern[A]) (S, TraversalAction)
	EnterTuplePattern(state S, p TuplePattern[A]) (S, TraversalAction)
	EnterConstructorPattern(state S, p ConstructorPattern[A]) (S, TraversalAction)
	EnterEmptyListPattern(state S, p EmptyListPattern[A]) (S, TraversalAction)
	EnterHeadTailPattern(state S, p HeadTailPattern[A]) (S, TraversalAction)
	EnterLiteralPattern(state S, p LiteralPattern[A]) (S, TraversalAction)
	EnterUnitPattern(state S, p UnitPattern[A]) (S, TraversalAction)

	ExitWildcardPattern(state S, p WildcardPattern[A]) S
	ExitAsPattern(state S, p AsPattern[A]) S
	ExitTuplePattern(state S, p TuplePattern[A]) S
	ExitConstructorPattern(state S, p ConstructorPattern[A]) S
	ExitEmptyListPattern(state S, p EmptyListPattern[A]) S
	ExitHeadTailPattern(state S, p HeadTailPattern[A]) S
	ExitLiteralPattern(state S, p LiteralPattern[A]) S
	ExitUnitPattern(state S, p UnitPattern[A]) S
}

// BasePatternVisitor provides default no-op implementations for PatternVisitor.
type BasePatternVisitor[A any, S any] struct{}

func (BasePatternVisitor[A, S]) EnterPattern(state S, p Pattern[A]) (S, TraversalAction) {
	return state, Continue
}
func (BasePatternVisitor[A, S]) ExitPattern(state S, p Pattern[A]) S { return state }

func (BasePatternVisitor[A, S]) EnterWildcardPattern(state S, p WildcardPattern[A]) (S, TraversalAction) {
	return state, Continue
}
func (BasePatternVisitor[A, S]) EnterAsPattern(state S, p AsPattern[A]) (S, TraversalAction) {
	return state, Continue
}
func (BasePatternVisitor[A, S]) EnterTuplePattern(state S, p TuplePattern[A]) (S, TraversalAction) {
	return state, Continue
}
func (BasePatternVisitor[A, S]) EnterConstructorPattern(state S, p ConstructorPattern[A]) (S, TraversalAction) {
	return state, Continue
}
func (BasePatternVisitor[A, S]) EnterEmptyListPattern(state S, p EmptyListPattern[A]) (S, TraversalAction) {
	return state, Continue
}
func (BasePatternVisitor[A, S]) EnterHeadTailPattern(state S, p HeadTailPattern[A]) (S, TraversalAction) {
	return state, Continue
}
func (BasePatternVisitor[A, S]) EnterLiteralPattern(state S, p LiteralPattern[A]) (S, TraversalAction) {
	return state, Continue
}
func (BasePatternVisitor[A, S]) EnterUnitPattern(state S, p UnitPattern[A]) (S, TraversalAction) {
	return state, Continue
}

func (BasePatternVisitor[A, S]) ExitWildcardPattern(state S, p WildcardPattern[A]) S     { return state }
func (BasePatternVisitor[A, S]) ExitAsPattern(state S, p AsPattern[A]) S                 { return state }
func (BasePatternVisitor[A, S]) ExitTuplePattern(state S, p TuplePattern[A]) S           { return state }
func (BasePatternVisitor[A, S]) ExitConstructorPattern(state S, p ConstructorPattern[A]) S { return state }
func (BasePatternVisitor[A, S]) ExitEmptyListPattern(state S, p EmptyListPattern[A]) S   { return state }
func (BasePatternVisitor[A, S]) ExitHeadTailPattern(state S, p HeadTailPattern[A]) S     { return state }
func (BasePatternVisitor[A, S]) ExitLiteralPattern(state S, p LiteralPattern[A]) S       { return state }
func (BasePatternVisitor[A, S]) ExitUnitPattern(state S, p UnitPattern[A]) S             { return state }

// WalkPattern traverses a Pattern tree using the provided visitor.
func WalkPattern[A any, S any](p Pattern[A], visitor PatternVisitor[A, S], state S) (S, bool) {
	if p == nil {
		return state, true
	}

	state, action := visitor.EnterPattern(state, p)
	if action == Stop {
		return state, false
	}
	if action == SkipChildren {
		return state, true
	}

	var completed bool
	switch v := p.(type) {
	case WildcardPattern[A]:
		state, completed = walkWildcardPattern(v, visitor, state)
	case AsPattern[A]:
		state, completed = walkAsPattern(v, visitor, state)
	case TuplePattern[A]:
		state, completed = walkTuplePattern(v, visitor, state)
	case ConstructorPattern[A]:
		state, completed = walkConstructorPattern(v, visitor, state)
	case EmptyListPattern[A]:
		state, completed = walkEmptyListPattern(v, visitor, state)
	case HeadTailPattern[A]:
		state, completed = walkHeadTailPattern(v, visitor, state)
	case LiteralPattern[A]:
		state, completed = walkLiteralPattern(v, visitor, state)
	case UnitPattern[A]:
		state, completed = walkUnitPattern(v, visitor, state)
	default:
		return state, true
	}

	if !completed {
		return state, false
	}

	state = visitor.ExitPattern(state, p)
	return state, true
}

func walkWildcardPattern[A any, S any](p WildcardPattern[A], v PatternVisitor[A, S], state S) (S, bool) {
	state, action := v.EnterWildcardPattern(state, p)
	if action == Stop {
		return state, false
	}
	if action != SkipChildren {
		state = v.ExitWildcardPattern(state, p)
	}
	return state, true
}

func walkAsPattern[A any, S any](p AsPattern[A], v PatternVisitor[A, S], state S) (S, bool) {
	state, action := v.EnterAsPattern(state, p)
	if action == Stop {
		return state, false
	}
	if action == SkipChildren {
		return state, true
	}

	var completed bool
	state, completed = WalkPattern(p.subject, v, state)
	if !completed {
		return state, false
	}

	state = v.ExitAsPattern(state, p)
	return state, true
}

func walkTuplePattern[A any, S any](p TuplePattern[A], v PatternVisitor[A, S], state S) (S, bool) {
	state, action := v.EnterTuplePattern(state, p)
	if action == Stop {
		return state, false
	}
	if action == SkipChildren {
		return state, true
	}

	for _, elem := range p.elements {
		var completed bool
		state, completed = WalkPattern(elem, v, state)
		if !completed {
			return state, false
		}
	}

	state = v.ExitTuplePattern(state, p)
	return state, true
}

func walkConstructorPattern[A any, S any](p ConstructorPattern[A], v PatternVisitor[A, S], state S) (S, bool) {
	state, action := v.EnterConstructorPattern(state, p)
	if action == Stop {
		return state, false
	}
	if action == SkipChildren {
		return state, true
	}

	for _, arg := range p.args {
		var completed bool
		state, completed = WalkPattern(arg, v, state)
		if !completed {
			return state, false
		}
	}

	state = v.ExitConstructorPattern(state, p)
	return state, true
}

func walkEmptyListPattern[A any, S any](p EmptyListPattern[A], v PatternVisitor[A, S], state S) (S, bool) {
	state, action := v.EnterEmptyListPattern(state, p)
	if action == Stop {
		return state, false
	}
	if action != SkipChildren {
		state = v.ExitEmptyListPattern(state, p)
	}
	return state, true
}

func walkHeadTailPattern[A any, S any](p HeadTailPattern[A], v PatternVisitor[A, S], state S) (S, bool) {
	state, action := v.EnterHeadTailPattern(state, p)
	if action == Stop {
		return state, false
	}
	if action == SkipChildren {
		return state, true
	}

	var completed bool
	state, completed = WalkPattern(p.head, v, state)
	if !completed {
		return state, false
	}

	state, completed = WalkPattern(p.tail, v, state)
	if !completed {
		return state, false
	}

	state = v.ExitHeadTailPattern(state, p)
	return state, true
}

func walkLiteralPattern[A any, S any](p LiteralPattern[A], v PatternVisitor[A, S], state S) (S, bool) {
	state, action := v.EnterLiteralPattern(state, p)
	if action == Stop {
		return state, false
	}
	if action != SkipChildren {
		state = v.ExitLiteralPattern(state, p)
	}
	return state, true
}

func walkUnitPattern[A any, S any](p UnitPattern[A], v PatternVisitor[A, S], state S) (S, bool) {
	state, action := v.EnterUnitPattern(state, p)
	if action == Stop {
		return state, false
	}
	if action != SkipChildren {
		state = v.ExitUnitPattern(state, p)
	}
	return state, true
}
