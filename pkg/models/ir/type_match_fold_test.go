package ir

import "testing"

const expectedNoErrorFmt = "expected no error, got %v"

func requireNoError(t *testing.T, err error) {
	t.Helper()
	if err != nil {
		t.Fatalf(expectedNoErrorFmt, err)
	}
}

func countTypeVariables(tpe Type[int]) int {
	return MustFoldType[int, int](tpe, TypeFold[int, int]{
		Variable: func(_ int, _ Name) int { return 1 },
		Reference: func(_ int, _ FQName, params []int) int {
			total := 0
			for _, p := range params {
				total += p
			}
			return total
		},
		Tuple: func(_ int, elems []int) int {
			total := 0
			for _, e := range elems {
				total += e
			}
			return total
		},
		Record: func(_ int, fields []FoldedField[int]) int {
			total := 0
			for _, f := range fields {
				total += f.Type()
			}
			return total
		},
		ExtensibleRecord: func(_ int, _ Name, fields []FoldedField[int]) int {
			total := 0
			for _, f := range fields {
				total += f.Type()
			}
			return total
		},
		Function: func(_ int, arg int, res int) int { return arg + res },
		Unit:     func(_ int) int { return 0 },
	})
}

func TestMatchTypeSelectsCorrectCase(t *testing.T) {
	name := NameFromParts([]string{"a"})
	n := NewTypeVariable[int](123, name)

	got, err := MatchType[int, string](n, TypeCases[int, string]{
		Variable: func(v TypeVariable[int]) string {
			if v.Attributes() != 123 {
				t.Fatalf("attributes: expected 123, got %v", v.Attributes())
			}
			if !v.Name().Equal(name) {
				t.Fatalf("name mismatch")
			}
			return "var"
		},
	})
	requireNoError(t, err)
	if got != "var" {
		t.Fatalf("expected 'var', got %q", got)
	}
}

func TestMatchTypeErrorsOnMissingHandler(t *testing.T) {
	n := NewTypeUnit[struct{}](struct{}{})

	_, err := MatchType[struct{}, string](n, TypeCases[struct{}, string]{})
	if err == nil {
		t.Fatal(expectedError)
	}
}

func TestFoldTypeCountsNodes(t *testing.T) {
	// Function( Unit, Tuple([Unit, Unit]) ) has 1 + 1 + 1 + 1 + 1 = 5 nodes.
	tree := NewTypeFunction[struct{}](
		struct{}{},
		NewTypeUnit[struct{}](struct{}{}),
		NewTypeTuple[struct{}](struct{}{}, []Type[struct{}]{
			NewTypeUnit[struct{}](struct{}{}),
			NewTypeUnit[struct{}](struct{}{}),
		}),
	)

	count, err := FoldType[struct{}, int](tree, TypeFold[struct{}, int]{
		Variable: func(_ struct{}, _ Name) int { return 1 },
		Reference: func(_ struct{}, _ FQName, params []int) int {
			total := 1
			for _, p := range params {
				total += p
			}
			return total
		},
		Tuple: func(_ struct{}, elems []int) int {
			total := 1
			for _, e := range elems {
				total += e
			}
			return total
		},
		Record: func(_ struct{}, fields []FoldedField[int]) int {
			total := 1
			for _, f := range fields {
				total += f.Type()
			}
			return total
		},
		ExtensibleRecord: func(_ struct{}, _ Name, fields []FoldedField[int]) int {
			total := 1
			for _, f := range fields {
				total += f.Type()
			}
			return total
		},
		Function: func(_ struct{}, arg int, res int) int { return 1 + arg + res },
		Unit:     func(_ struct{}) int { return 1 },
	})
	requireNoError(t, err)
	if count != 5 {
		t.Fatalf("expected 5, got %d", count)
	}
}

func TestMapTypeRewritesUnits(t *testing.T) {
	// Rewrite every Unit node into a Variable node.
	name := NameFromParts([]string{"u"})

	tree := NewTypeFunction[int](
		1,
		NewTypeUnit[int](2),
		NewTypeTuple[int](3, []Type[int]{
			NewTypeUnit[int](4),
			NewTypeUnit[int](5),
		}),
	)

	mapped, err := MapType[int](tree, func(n Type[int]) (Type[int], error) {
		switch v := n.(type) {
		case TypeUnit[int]:
			return NewTypeVariable[int](v.Attributes(), name), nil
		default:
			return n, nil
		}
	})
	requireNoError(t, err)

	// We had 3 units (arg + 2 tuple elems), so after rewrite we should have 3 variables.
	if got := countTypeVariables(mapped); got != 3 {
		t.Fatalf("expected 3 variables, got %d", got)
	}
}

func TestMapTypeAttributesTransformsAttributes(t *testing.T) {
	tree := NewTypeFunction[int](
		10,
		NewTypeUnit[int](20),
		NewTypeUnit[int](30),
	)

	mapped, err := MapTypeAttributes[int, string](tree, func(a int) string {
		return "attr"
	})
	requireNoError(t, err)

	// Sanity-check that the root and children now have string attributes.
	root, ok := mapped.(TypeFunction[string])
	if !ok {
		t.Fatalf("expected TypeFunction[string], got %T", mapped)
	}
	if root.Attributes() != "attr" {
		t.Fatalf("expected root attributes to be 'attr', got %q", root.Attributes())
	}
	if _, ok := root.Argument().(TypeUnit[string]); !ok {
		t.Fatalf("expected arg to be TypeUnit[string], got %T", root.Argument())
	}
	if _, ok := root.Result().(TypeUnit[string]); !ok {
		t.Fatalf("expected result to be TypeUnit[string], got %T", root.Result())
	}
}
