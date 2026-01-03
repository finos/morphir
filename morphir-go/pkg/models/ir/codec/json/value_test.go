package json

import (
	"encoding/json"
	"testing"

	ir "github.com/finos/morphir-go/pkg/models/ir"
)

// encodeValueUnitAttr wraps encodeUnitAttr to match ValueAttrEncoder signature
func encodeValueUnitAttr(u unitAttr) (json.RawMessage, error) {
	return encodeUnitAttr(u)
}

// decodeValueUnitAttr wraps decodeUnitAttr to match ValueAttrDecoder signature
func decodeValueUnitAttr(raw json.RawMessage) (unitAttr, error) {
	return decodeUnitAttr(raw)
}

func TestValueRoundTripV3(t *testing.T) {
	opts := Options{FormatVersion: FormatV3}

	// Build a complex nested value including patterns
	my := ir.NameFromParts([]string{"my"})
	mod := ir.PathFromParts([]ir.Name{my, ir.NameFromParts([]string{"mod"})})
	pkg := ir.PathFromParts([]ir.Name{my, ir.NameFromParts([]string{"pkg"})})
	fq := ir.FQNameFromParts(pkg, mod, ir.NameFromParts([]string{"add"}))

	// Lambda: \x -> if x > 0 then x else 0
	xName := ir.NameFromParts([]string{"x"})

	// Create a PatternMatch value with patterns
	patternMatch := ir.NewPatternMatchValue[unitAttr, unitAttr](
		unitAttr{},
		ir.NewVariableValue[unitAttr, unitAttr](unitAttr{}, xName),
		[]ir.PatternMatchCase[unitAttr, unitAttr]{
			ir.PatternMatchCaseFromParts[unitAttr, unitAttr](
				ir.NewLiteralPattern(unitAttr{}, ir.NewWholeNumberLiteral(0)),
				ir.NewLiteralValue[unitAttr, unitAttr](unitAttr{}, ir.NewStringLiteral("zero")),
			),
			ir.PatternMatchCaseFromParts[unitAttr, unitAttr](
				ir.NewWildcardPattern(unitAttr{}),
				ir.NewLiteralValue[unitAttr, unitAttr](unitAttr{}, ir.NewStringLiteral("nonzero")),
			),
		},
	)

	// Lambda wrapping the pattern match
	lambda := ir.NewLambdaValue[unitAttr, unitAttr](
		unitAttr{},
		ir.NewAsPattern(unitAttr{}, ir.NewWildcardPattern(unitAttr{}), xName),
		patternMatch,
	)

	// IfThenElse
	ifThenElse := ir.NewIfThenElseValue[unitAttr, unitAttr](
		unitAttr{},
		ir.NewLiteralValue[unitAttr, unitAttr](unitAttr{}, ir.NewBoolLiteral(true)),
		ir.NewLiteralValue[unitAttr, unitAttr](unitAttr{}, ir.NewWholeNumberLiteral(1)),
		ir.NewLiteralValue[unitAttr, unitAttr](unitAttr{}, ir.NewWholeNumberLiteral(0)),
	)

	// Apply: add x y
	apply := ir.NewApplyValue[unitAttr, unitAttr](
		unitAttr{},
		ir.NewApplyValue[unitAttr, unitAttr](
			unitAttr{},
			ir.NewReferenceValue[unitAttr, unitAttr](unitAttr{}, fq),
			ir.NewVariableValue[unitAttr, unitAttr](unitAttr{}, xName),
		),
		ir.NewLiteralValue[unitAttr, unitAttr](unitAttr{}, ir.NewWholeNumberLiteral(5)),
	)

	// Tuple
	tuple := ir.NewTupleValue[unitAttr, unitAttr](unitAttr{}, []ir.Value[unitAttr, unitAttr]{
		ir.NewLiteralValue[unitAttr, unitAttr](unitAttr{}, ir.NewStringLiteral("hello")),
		ir.NewLiteralValue[unitAttr, unitAttr](unitAttr{}, ir.NewWholeNumberLiteral(42)),
		ir.NewUnitValue[unitAttr, unitAttr](unitAttr{}),
	})

	// List
	list := ir.NewListValue[unitAttr, unitAttr](unitAttr{}, []ir.Value[unitAttr, unitAttr]{
		ir.NewLiteralValue[unitAttr, unitAttr](unitAttr{}, ir.NewWholeNumberLiteral(1)),
		ir.NewLiteralValue[unitAttr, unitAttr](unitAttr{}, ir.NewWholeNumberLiteral(2)),
		ir.NewLiteralValue[unitAttr, unitAttr](unitAttr{}, ir.NewWholeNumberLiteral(3)),
	})

	// Record
	record := ir.NewRecordValue[unitAttr, unitAttr](unitAttr{}, []ir.RecordField[unitAttr, unitAttr]{
		ir.RecordFieldFromParts[unitAttr, unitAttr](ir.NameFromParts([]string{"name"}), ir.NewLiteralValue[unitAttr, unitAttr](unitAttr{}, ir.NewStringLiteral("test"))),
		ir.RecordFieldFromParts[unitAttr, unitAttr](ir.NameFromParts([]string{"value"}), ir.NewLiteralValue[unitAttr, unitAttr](unitAttr{}, ir.NewWholeNumberLiteral(100))),
	})

	// Constructor
	constructor := ir.NewConstructorValue[unitAttr, unitAttr](unitAttr{}, fq)

	// Field access
	field := ir.NewFieldValue[unitAttr, unitAttr](
		unitAttr{},
		ir.NewVariableValue[unitAttr, unitAttr](unitAttr{}, xName),
		ir.NameFromParts([]string{"foo"}),
	)

	// FieldFunction
	fieldFunction := ir.NewFieldFunctionValue[unitAttr, unitAttr](unitAttr{}, ir.NameFromParts([]string{"bar"}))

	testCases := []struct {
		name  string
		value ir.Value[unitAttr, unitAttr]
	}{
		{"Lambda", lambda},
		{"IfThenElse", ifThenElse},
		{"Apply", apply},
		{"Tuple", tuple},
		{"List", list},
		{"Record", record},
		{"PatternMatch", patternMatch},
		{"Constructor", constructor},
		{"Field", field},
		{"FieldFunction", fieldFunction},
		{"Unit", ir.NewUnitValue[unitAttr, unitAttr](unitAttr{})},
		{"Literal", ir.NewLiteralValue[unitAttr, unitAttr](unitAttr{}, ir.NewStringLiteral("test"))},
		{"Variable", ir.NewVariableValue[unitAttr, unitAttr](unitAttr{}, xName)},
		{"Reference", ir.NewReferenceValue[unitAttr, unitAttr](unitAttr{}, fq)},
	}

	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			data, err := EncodeValue(opts, encodeUnitAttr, encodeValueUnitAttr, tc.value)
			if err != nil {
				t.Fatalf("EncodeValue: %v", err)
			}

			decoded, err := DecodeValue(opts, decodeUnitAttr, decodeValueUnitAttr, data)
			if err != nil {
				t.Fatalf("DecodeValue: %v", err)
			}

			if !ir.EqualValue(
				func(unitAttr, unitAttr) bool { return true },
				func(unitAttr, unitAttr) bool { return true },
				tc.value, decoded,
			) {
				t.Fatalf("expected structural equality after roundtrip")
			}
		})
	}
}

func TestValueVersionedTags(t *testing.T) {
	// Test that v1 uses snake_case and v2/v3 uses PascalCase tags
	testCases := []struct {
		name  string
		value ir.Value[unitAttr, unitAttr]
		v1Tag string
		v3Tag string
	}{
		{
			"Literal",
			ir.NewLiteralValue[unitAttr, unitAttr](unitAttr{}, ir.NewStringLiteral("test")),
			"literal",
			"Literal",
		},
		{
			"IfThenElse",
			ir.NewIfThenElseValue[unitAttr, unitAttr](
				unitAttr{},
				ir.NewLiteralValue[unitAttr, unitAttr](unitAttr{}, ir.NewBoolLiteral(true)),
				ir.NewUnitValue[unitAttr, unitAttr](unitAttr{}),
				ir.NewUnitValue[unitAttr, unitAttr](unitAttr{}),
			),
			"if_then_else",
			"IfThenElse",
		},
		{
			"FieldFunction",
			ir.NewFieldFunctionValue[unitAttr, unitAttr](unitAttr{}, ir.NameFromParts([]string{"foo"})),
			"field_function",
			"FieldFunction",
		},
		{
			"PatternMatch",
			ir.NewPatternMatchValue[unitAttr, unitAttr](
				unitAttr{},
				ir.NewUnitValue[unitAttr, unitAttr](unitAttr{}),
				[]ir.PatternMatchCase[unitAttr, unitAttr]{},
			),
			"pattern_match",
			"PatternMatch",
		},
		{
			"UpdateRecord",
			ir.NewUpdateRecordValue[unitAttr, unitAttr](
				unitAttr{},
				ir.NewVariableValue[unitAttr, unitAttr](unitAttr{}, ir.NameFromParts([]string{"r"})),
				[]ir.RecordField[unitAttr, unitAttr]{},
			),
			"update_record",
			"UpdateRecord",
		},
		{
			"Unit",
			ir.NewUnitValue[unitAttr, unitAttr](unitAttr{}),
			"unit",
			"Unit",
		},
	}

	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			// Test v1 tag
			dataV1, err := EncodeValue(Options{FormatVersion: FormatV1}, encodeUnitAttr, encodeValueUnitAttr, tc.value)
			if err != nil {
				t.Fatalf("EncodeValue(v1): %v", err)
			}
			var rawV1 []json.RawMessage
			if err := json.Unmarshal(dataV1, &rawV1); err != nil {
				t.Fatalf("unmarshal v1: %v", err)
			}
			var tagV1 string
			if err := json.Unmarshal(rawV1[0], &tagV1); err != nil {
				t.Fatalf("tag v1: %v", err)
			}
			if tagV1 != tc.v1Tag {
				t.Fatalf("expected v1 tag %q, got %q", tc.v1Tag, tagV1)
			}

			// Test v3 tag
			dataV3, err := EncodeValue(Options{FormatVersion: FormatV3}, encodeUnitAttr, encodeValueUnitAttr, tc.value)
			if err != nil {
				t.Fatalf("EncodeValue(v3): %v", err)
			}
			var rawV3 []json.RawMessage
			if err := json.Unmarshal(dataV3, &rawV3); err != nil {
				t.Fatalf("unmarshal v3: %v", err)
			}
			var tagV3 string
			if err := json.Unmarshal(rawV3[0], &tagV3); err != nil {
				t.Fatalf("tag v3: %v", err)
			}
			if tagV3 != tc.v3Tag {
				t.Fatalf("expected v3 tag %q, got %q", tc.v3Tag, tagV3)
			}
		})
	}
}

func TestValueDecodeRejectsWrongVersion(t *testing.T) {
	// Encode with v3 and try to decode with v1 - should fail
	value := ir.NewIfThenElseValue[unitAttr, unitAttr](
		unitAttr{},
		ir.NewLiteralValue[unitAttr, unitAttr](unitAttr{}, ir.NewBoolLiteral(true)),
		ir.NewLiteralValue[unitAttr, unitAttr](unitAttr{}, ir.NewWholeNumberLiteral(1)),
		ir.NewLiteralValue[unitAttr, unitAttr](unitAttr{}, ir.NewWholeNumberLiteral(0)),
	)

	dataV3, err := EncodeValue(Options{FormatVersion: FormatV3}, encodeUnitAttr, encodeValueUnitAttr, value)
	if err != nil {
		t.Fatalf("EncodeValue(v3): %v", err)
	}

	if _, err := DecodeValue(Options{FormatVersion: FormatV1}, decodeUnitAttr, decodeValueUnitAttr, dataV3); err == nil {
		t.Fatalf("expected v1 decode to fail on v3 payload")
	}
}

func TestValueDestructureRoundTrip(t *testing.T) {
	opts := Options{FormatVersion: FormatV3}

	xName := ir.NameFromParts([]string{"x"})
	yName := ir.NameFromParts([]string{"y"})

	destructure := ir.NewDestructureValue[unitAttr, unitAttr](
		unitAttr{},
		ir.NewTuplePattern(unitAttr{}, []ir.Pattern[unitAttr]{
			ir.NewAsPattern(unitAttr{}, ir.NewWildcardPattern(unitAttr{}), xName),
			ir.NewAsPattern(unitAttr{}, ir.NewWildcardPattern(unitAttr{}), yName),
		}),
		ir.NewTupleValue[unitAttr, unitAttr](unitAttr{}, []ir.Value[unitAttr, unitAttr]{
			ir.NewLiteralValue[unitAttr, unitAttr](unitAttr{}, ir.NewWholeNumberLiteral(1)),
			ir.NewLiteralValue[unitAttr, unitAttr](unitAttr{}, ir.NewWholeNumberLiteral(2)),
		}),
		ir.NewVariableValue[unitAttr, unitAttr](unitAttr{}, xName),
	)

	data, err := EncodeValue(opts, encodeUnitAttr, encodeValueUnitAttr, destructure)
	if err != nil {
		t.Fatalf("EncodeValue: %v", err)
	}

	decoded, err := DecodeValue(opts, decodeUnitAttr, decodeValueUnitAttr, data)
	if err != nil {
		t.Fatalf("DecodeValue: %v", err)
	}

	if !ir.EqualValue(
		func(unitAttr, unitAttr) bool { return true },
		func(unitAttr, unitAttr) bool { return true },
		destructure, decoded,
	) {
		t.Fatalf("expected structural equality after roundtrip")
	}
}

func TestValueLetDefinitionRoundTrip(t *testing.T) {
	opts := Options{FormatVersion: FormatV3}

	xName := ir.NameFromParts([]string{"x"})

	// Create a simple let definition: let x = 42 in x
	def := ir.NewValueDefinition[unitAttr, unitAttr](
		[]ir.ValueDefinitionInput[unitAttr, unitAttr]{}, // no input types
		ir.NewTypeUnit[unitAttr](unitAttr{}),            // output type
		ir.NewLiteralValue[unitAttr, unitAttr](unitAttr{}, ir.NewWholeNumberLiteral(42)),
	)

	letDef := ir.NewLetDefinitionValue[unitAttr, unitAttr](
		unitAttr{},
		xName,
		def,
		ir.NewVariableValue[unitAttr, unitAttr](unitAttr{}, xName),
	)

	data, err := EncodeValue(opts, encodeUnitAttr, encodeValueUnitAttr, letDef)
	if err != nil {
		t.Fatalf("EncodeValue: %v", err)
	}

	decoded, err := DecodeValue(opts, decodeUnitAttr, decodeValueUnitAttr, data)
	if err != nil {
		t.Fatalf("DecodeValue: %v", err)
	}

	if !ir.EqualValue(
		func(unitAttr, unitAttr) bool { return true },
		func(unitAttr, unitAttr) bool { return true },
		letDef, decoded,
	) {
		t.Fatalf("expected structural equality after roundtrip")
	}
}

func TestValueLetRecursionRoundTrip(t *testing.T) {
	opts := Options{FormatVersion: FormatV3}

	fName := ir.NameFromParts([]string{"f"})
	xName := ir.NameFromParts([]string{"x"})

	// Create a recursive let: let rec f = \x -> f x in f
	def := ir.NewValueDefinition[unitAttr, unitAttr](
		[]ir.ValueDefinitionInput[unitAttr, unitAttr]{},
		ir.NewTypeUnit[unitAttr](unitAttr{}),
		ir.NewLambdaValue[unitAttr, unitAttr](
			unitAttr{},
			ir.NewAsPattern(unitAttr{}, ir.NewWildcardPattern(unitAttr{}), xName),
			ir.NewApplyValue[unitAttr, unitAttr](
				unitAttr{},
				ir.NewVariableValue[unitAttr, unitAttr](unitAttr{}, fName),
				ir.NewVariableValue[unitAttr, unitAttr](unitAttr{}, xName),
			),
		),
	)

	letRec := ir.NewLetRecursionValue[unitAttr, unitAttr](
		unitAttr{},
		[]ir.NamedValueDefinition[unitAttr, unitAttr]{
			ir.NamedValueDefinitionFromParts(fName, def),
		},
		ir.NewVariableValue[unitAttr, unitAttr](unitAttr{}, fName),
	)

	data, err := EncodeValue(opts, encodeUnitAttr, encodeValueUnitAttr, letRec)
	if err != nil {
		t.Fatalf("EncodeValue: %v", err)
	}

	decoded, err := DecodeValue(opts, decodeUnitAttr, decodeValueUnitAttr, data)
	if err != nil {
		t.Fatalf("DecodeValue: %v", err)
	}

	if !ir.EqualValue(
		func(unitAttr, unitAttr) bool { return true },
		func(unitAttr, unitAttr) bool { return true },
		letRec, decoded,
	) {
		t.Fatalf("expected structural equality after roundtrip")
	}
}
