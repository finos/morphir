package ir

import (
	"testing"

	"github.com/stretchr/testify/require"
)

// nodeCountingVisitor counts visited type nodes
type nodeCountingVisitor struct {
	BaseTypeVisitor[int, int]
}

func (v nodeCountingVisitor) EnterType(count int, t Type[int]) (int, TraversalAction) {
	return count + 1, Continue
}

func TestWalkType_SimpleVariable(t *testing.T) {
	typ := NewTypeVariable[int](42, NameFromString("a"))
	visitor := nodeCountingVisitor{}

	count, completed := WalkType(typ, visitor, 0)

	require.True(t, completed)
	require.Equal(t, 1, count)
}

func TestWalkType_Function(t *testing.T) {
	// Build: Int -> String -> Bool (curried function)
	argType := NewTypeVariable[int](1, NameFromString("Int"))
	midType := NewTypeVariable[int](2, NameFromString("String"))
	retType := NewTypeVariable[int](3, NameFromString("Bool"))

	innerFunc := NewTypeFunction[int](10, midType, retType)
	outerFunc := NewTypeFunction[int](20, argType, innerFunc)

	visitor := nodeCountingVisitor{}
	count, completed := WalkType(outerFunc, visitor, 0)

	require.True(t, completed)
	// 5 nodes: outerFunc, argType, innerFunc, midType, retType
	require.Equal(t, 5, count)
}

func TestWalkType_Tuple(t *testing.T) {
	elem1 := NewTypeVariable[int](1, NameFromString("a"))
	elem2 := NewTypeVariable[int](2, NameFromString("b"))
	elem3 := NewTypeVariable[int](3, NameFromString("c"))

	tuple := NewTypeTuple[int](0, []Type[int]{elem1, elem2, elem3})

	visitor := nodeCountingVisitor{}
	count, completed := WalkType(tuple, visitor, 0)

	require.True(t, completed)
	// 4 nodes: tuple + 3 elements
	require.Equal(t, 4, count)
}

func TestWalkType_Record(t *testing.T) {
	field1Type := NewTypeVariable[int](1, NameFromString("Int"))
	field2Type := NewTypeVariable[int](2, NameFromString("String"))

	record := NewTypeRecord[int](0, []Field[int]{
		FieldFromParts(NameFromString("age"), field1Type),
		FieldFromParts(NameFromString("name"), field2Type),
	})

	visitor := nodeCountingVisitor{}
	count, completed := WalkType(record, visitor, 0)

	require.True(t, completed)
	// 3 nodes: record + 2 field types
	require.Equal(t, 3, count)
}

func TestWalkType_Reference(t *testing.T) {
	param1 := NewTypeVariable[int](1, NameFromString("a"))
	param2 := NewTypeVariable[int](2, NameFromString("b"))

	fqn, err := ParseFQName("Morphir.SDK:List:List")
	require.NoError(t, err)
	ref := NewTypeReference[int](0, fqn, []Type[int]{param1, param2})

	visitor := nodeCountingVisitor{}
	count, completed := WalkType(ref, visitor, 0)

	require.True(t, completed)
	// 3 nodes: reference + 2 type params
	require.Equal(t, 3, count)
}

func TestWalkType_Unit(t *testing.T) {
	unit := NewTypeUnit[int](0)

	visitor := nodeCountingVisitor{}
	count, completed := WalkType(unit, visitor, 0)

	require.True(t, completed)
	require.Equal(t, 1, count)
}

func TestWalkType_Nil(t *testing.T) {
	visitor := nodeCountingVisitor{}
	count, completed := WalkType[int](nil, visitor, 0)

	require.True(t, completed)
	require.Equal(t, 0, count)
}

// stoppingVisitor stops after visiting N nodes
type stoppingVisitor struct {
	BaseTypeVisitor[int, int]
	stopAfter int
}

func (v stoppingVisitor) EnterType(count int, t Type[int]) (int, TraversalAction) {
	count++
	if count >= v.stopAfter {
		return count, Stop
	}
	return count, Continue
}

func TestWalkType_StopTraversal(t *testing.T) {
	elem1 := NewTypeVariable[int](1, NameFromString("a"))
	elem2 := NewTypeVariable[int](2, NameFromString("b"))
	elem3 := NewTypeVariable[int](3, NameFromString("c"))
	tuple := NewTypeTuple[int](0, []Type[int]{elem1, elem2, elem3})

	visitor := stoppingVisitor{stopAfter: 2}
	count, completed := WalkType(tuple, visitor, 0)

	require.False(t, completed)
	require.Equal(t, 2, count)
}

// skippingVisitor skips children of tuples
type skippingVisitor struct {
	BaseTypeVisitor[int, int]
}

func (v skippingVisitor) EnterType(count int, t Type[int]) (int, TraversalAction) {
	return count + 1, Continue
}

func (v skippingVisitor) EnterTypeTuple(count int, t TypeTuple[int]) (int, TraversalAction) {
	return count, SkipChildren
}

func TestWalkType_SkipChildren(t *testing.T) {
	elem1 := NewTypeVariable[int](1, NameFromString("a"))
	elem2 := NewTypeVariable[int](2, NameFromString("b"))
	tuple := NewTypeTuple[int](0, []Type[int]{elem1, elem2})

	visitor := skippingVisitor{}
	count, completed := WalkType(tuple, visitor, 0)

	require.True(t, completed)
	// Only 1 node: the tuple itself (children skipped)
	require.Equal(t, 1, count)
}

// exitTrackingVisitor tracks enter/exit order
type exitTrackingVisitor struct {
	BaseTypeVisitor[int, []string]
}

func (v exitTrackingVisitor) EnterType(events []string, t Type[int]) ([]string, TraversalAction) {
	return append(events, "enter"), Continue
}

func (v exitTrackingVisitor) ExitType(events []string, t Type[int]) []string {
	return append(events, "exit")
}

func TestWalkType_EnterExitOrder(t *testing.T) {
	argType := NewTypeVariable[int](1, NameFromString("a"))
	retType := NewTypeVariable[int](2, NameFromString("b"))
	funcType := NewTypeFunction[int](0, argType, retType)

	visitor := exitTrackingVisitor{}
	events, completed := WalkType(funcType, visitor, []string{})

	require.True(t, completed)
	// Expected order: enter func, enter arg, exit arg, enter ret, exit ret, exit func
	expected := []string{"enter", "enter", "exit", "enter", "exit", "exit"}
	require.Equal(t, expected, events)
}

// patternCountingVisitor counts visited pattern nodes
type patternCountingVisitor struct {
	BasePatternVisitor[int, int]
}

func (v patternCountingVisitor) EnterPattern(count int, p Pattern[int]) (int, TraversalAction) {
	return count + 1, Continue
}

func TestWalkPattern_Wildcard(t *testing.T) {
	pattern := NewWildcardPattern[int](0)
	visitor := patternCountingVisitor{}

	count, completed := WalkPattern(pattern, visitor, 0)

	require.True(t, completed)
	require.Equal(t, 1, count)
}

func TestWalkPattern_As(t *testing.T) {
	inner := NewWildcardPattern[int](1)
	asPattern := NewAsPattern[int](0, inner, NameFromString("x"))

	visitor := patternCountingVisitor{}
	count, completed := WalkPattern(asPattern, visitor, 0)

	require.True(t, completed)
	// 2 nodes: as pattern + wildcard
	require.Equal(t, 2, count)
}

func TestWalkPattern_Tuple(t *testing.T) {
	elem1 := NewWildcardPattern[int](1)
	elem2 := NewWildcardPattern[int](2)
	elem3 := NewWildcardPattern[int](3)
	tuple := NewTuplePattern[int](0, []Pattern[int]{elem1, elem2, elem3})

	visitor := patternCountingVisitor{}
	count, completed := WalkPattern(tuple, visitor, 0)

	require.True(t, completed)
	// 4 nodes: tuple + 3 wildcards
	require.Equal(t, 4, count)
}

func TestWalkPattern_Constructor(t *testing.T) {
	arg1 := NewWildcardPattern[int](1)
	arg2 := NewWildcardPattern[int](2)
	fqn, err := ParseFQName("Morphir.SDK:Maybe:Just")
	require.NoError(t, err)
	constructor := NewConstructorPattern[int](0, fqn, []Pattern[int]{arg1, arg2})

	visitor := patternCountingVisitor{}
	count, completed := WalkPattern(constructor, visitor, 0)

	require.True(t, completed)
	// 3 nodes: constructor + 2 args
	require.Equal(t, 3, count)
}

func TestWalkPattern_HeadTail(t *testing.T) {
	head := NewWildcardPattern[int](1)
	tail := NewWildcardPattern[int](2)
	headTail := NewHeadTailPattern[int](0, head, tail)

	visitor := patternCountingVisitor{}
	count, completed := WalkPattern(headTail, visitor, 0)

	require.True(t, completed)
	// 3 nodes: headTail + head + tail
	require.Equal(t, 3, count)
}

func TestWalkPattern_Nil(t *testing.T) {
	visitor := patternCountingVisitor{}
	count, completed := WalkPattern[int](nil, visitor, 0)

	require.True(t, completed)
	require.Equal(t, 0, count)
}

// typeNameCollector collects all type variable names
type typeNameCollector struct {
	BaseTypeVisitor[int, []string]
}

func (v typeNameCollector) EnterTypeVariable(names []string, t TypeVariable[int]) ([]string, TraversalAction) {
	return append(names, t.Name().ToTitleCase()), Continue
}

func TestWalkType_CollectNames(t *testing.T) {
	// Build: (a, b) -> c
	a := NewTypeVariable[int](1, NameFromString("a"))
	b := NewTypeVariable[int](2, NameFromString("b"))
	c := NewTypeVariable[int](3, NameFromString("c"))
	tuple := NewTypeTuple[int](4, []Type[int]{a, b})
	funcType := NewTypeFunction[int](5, tuple, c)

	visitor := typeNameCollector{}
	names, completed := WalkType(funcType, visitor, []string{})

	require.True(t, completed)
	// ToTitleCase capitalizes single-word names
	require.Equal(t, []string{"A", "B", "C"}, names)
}
