package json

import (
	"encoding/json"
	"testing"

	ir "github.com/finos/morphir-go/pkg/models/ir"
)

type unitAttr struct{}

func encodeUnitAttr(unitAttr) (json.RawMessage, error) {
	// Morphir's unit is encoded as an empty JSON array.
	return json.RawMessage("[]"), nil
}

func decodeUnitAttr(raw json.RawMessage) (unitAttr, error) {
	var items []any
	if err := json.Unmarshal(raw, &items); err != nil {
		return unitAttr{}, err
	}
	if len(items) != 0 {
		return unitAttr{}, &json.UnmarshalTypeError{Value: "non-empty unit", Type: nil}
	}
	return unitAttr{}, nil
}

func TestTypeRoundTripV3(t *testing.T) {
	opts := Options{FormatVersion: FormatV3}

	x := ir.NameFromParts([]string{"x"})
	foo := ir.NameFromParts([]string{"foo"})
	mod := ir.PathFromParts([]ir.Name{ir.NameFromParts([]string{"my"}), ir.NameFromParts([]string{"mod"})})
	pkg := ir.PathFromParts([]ir.Name{ir.NameFromParts([]string{"my"}), ir.NameFromParts([]string{"pkg"})})
	fq := ir.FQNameFromParts(pkg, mod, foo)

	// Function( Reference foo [Variable x], Record {foo: Unit} )
	ref := ir.NewTypeReference(unitAttr{}, fq, []ir.Type[unitAttr]{ir.NewTypeVariable(unitAttr{}, x)})
	rec := ir.NewTypeRecord(unitAttr{}, []ir.Field[unitAttr]{
		ir.FieldFromParts[unitAttr](foo, ir.NewTypeUnit(unitAttr{})),
	})
	tpe := ir.NewTypeFunction(unitAttr{}, ref, rec)

	data, err := EncodeType(opts, encodeUnitAttr, tpe)
	if err != nil {
		t.Fatalf("EncodeType: %v", err)
	}

	decoded, err := DecodeType(opts, decodeUnitAttr, data)
	if err != nil {
		t.Fatalf("DecodeType: %v", err)
	}

	if !ir.EqualType(func(unitAttr, unitAttr) bool { return true }, tpe, decoded) {
		t.Fatalf("expected structural equality after roundtrip")
	}
}

func TestTypeVersionedTagsAndFieldShape(t *testing.T) {
	foo := ir.NameFromParts([]string{"foo"})
	rec := ir.NewTypeRecord(unitAttr{}, []ir.Field[unitAttr]{
		ir.FieldFromParts[unitAttr](foo, ir.NewTypeUnit(unitAttr{})),
	})

	// v1
	dataV1, err := EncodeType(Options{FormatVersion: FormatV1}, encodeUnitAttr, rec)
	if err != nil {
		t.Fatalf("EncodeType(v1): %v", err)
	}

	var rawV1 []json.RawMessage
	if err := json.Unmarshal(dataV1, &rawV1); err != nil {
		t.Fatalf("unmarshal v1: %v", err)
	}
	var tagV1 string
	if err := json.Unmarshal(rawV1[0], &tagV1); err != nil {
		t.Fatalf("tag v1: %v", err)
	}
	if tagV1 != "record" {
		t.Fatalf("expected v1 tag 'record', got %q", tagV1)
	}
	var fieldsV1 []json.RawMessage
	if err := json.Unmarshal(rawV1[2], &fieldsV1); err != nil {
		t.Fatalf("fields v1: %v", err)
	}
	var fieldAsArray []json.RawMessage
	if err := json.Unmarshal(fieldsV1[0], &fieldAsArray); err != nil {
		t.Fatalf("expected v1 field to be array [name,tpe]: %v", err)
	}
	if len(fieldAsArray) != 2 {
		t.Fatalf("expected v1 field array length 2, got %d", len(fieldAsArray))
	}

	// v3
	dataV3, err := EncodeType(Options{FormatVersion: FormatV3}, encodeUnitAttr, rec)
	if err != nil {
		t.Fatalf("EncodeType(v3): %v", err)
	}
	var rawV3 []json.RawMessage
	if err := json.Unmarshal(dataV3, &rawV3); err != nil {
		t.Fatalf("unmarshal v3: %v", err)
	}
	var tagV3 string
	if err := json.Unmarshal(rawV3[0], &tagV3); err != nil {
		t.Fatalf("tag v3: %v", err)
	}
	if tagV3 != "Record" {
		t.Fatalf("expected v3 tag 'Record', got %q", tagV3)
	}
	var fieldsV3 []json.RawMessage
	if err := json.Unmarshal(rawV3[2], &fieldsV3); err != nil {
		t.Fatalf("fields v3: %v", err)
	}
	var fieldAsObj map[string]json.RawMessage
	if err := json.Unmarshal(fieldsV3[0], &fieldAsObj); err != nil {
		t.Fatalf("expected v3 field to be object {name,tpe}: %v", err)
	}
	if _, ok := fieldAsObj["name"]; !ok {
		t.Fatalf("expected v3 field to have key 'name'")
	}
	if _, ok := fieldAsObj["tpe"]; !ok {
		t.Fatalf("expected v3 field to have key 'tpe'")
	}
}

func TestTypeDecodeRejectsWrongVersion(t *testing.T) {
	foo := ir.NameFromParts([]string{"foo"})
	rec := ir.NewTypeRecord(unitAttr{}, []ir.Field[unitAttr]{
		ir.FieldFromParts[unitAttr](foo, ir.NewTypeUnit(unitAttr{})),
	})

	dataV3, err := EncodeType(Options{FormatVersion: FormatV3}, encodeUnitAttr, rec)
	if err != nil {
		t.Fatalf("EncodeType(v3): %v", err)
	}

	if _, err := DecodeType(Options{FormatVersion: FormatV1}, decodeUnitAttr, dataV3); err == nil {
		t.Fatalf("expected v1 decode to fail on v3 payload")
	}
}
