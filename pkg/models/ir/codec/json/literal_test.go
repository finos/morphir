package json

import (
	"encoding/json"
	"testing"

	ir "github.com/finos/morphir/pkg/models/ir"
)

func TestLiteralRoundTripV3(t *testing.T) {
	opts := Options{FormatVersion: FormatV3}

	dec, ok := ir.DecimalFromString("123.450")
	if !ok {
		t.Fatalf("expected decimal to parse")
	}
	cases := []ir.Literal{
		ir.NewBoolLiteral(true),
		ir.NewCharLiteral('Z'),
		ir.NewStringLiteral("hello"),
		ir.NewWholeNumberLiteral(42),
		ir.NewFloatLiteral(1.25),
		ir.NewDecimalLiteral(dec),
	}

	for _, lit := range cases {
		data, err := EncodeLiteral(opts, lit)
		if err != nil {
			t.Fatalf("EncodeLiteral: %v", err)
		}
		got, err := DecodeLiteral(opts, data)
		if err != nil {
			t.Fatalf("DecodeLiteral: %v", err)
		}
		if !ir.EqualLiteral(lit, got) {
			t.Fatalf("roundtrip mismatch: %#v vs %#v", lit, got)
		}
	}
}

func TestLiteralVersionedTags(t *testing.T) {
	dec, ok := ir.DecimalFromString("1.25")
	if !ok {
		t.Fatalf("expected decimal to parse")
	}
	lit := ir.NewDecimalLiteral(dec)

	dataV1, err := EncodeLiteral(Options{FormatVersion: FormatV1}, lit)
	if err != nil {
		t.Fatalf("EncodeLiteral(v1): %v", err)
	}
	var rawV1 []json.RawMessage
	if err := json.Unmarshal(dataV1, &rawV1); err != nil {
		t.Fatalf("unmarshal v1: %v", err)
	}
	var tagV1 string
	if err := json.Unmarshal(rawV1[0], &tagV1); err != nil {
		t.Fatalf("tag v1: %v", err)
	}
	if tagV1 != "decimal_literal" {
		t.Fatalf("expected v1 tag 'decimal_literal', got %q", tagV1)
	}

	dataV3, err := EncodeLiteral(Options{FormatVersion: FormatV3}, lit)
	if err != nil {
		t.Fatalf("EncodeLiteral(v3): %v", err)
	}
	var rawV3 []json.RawMessage
	if err := json.Unmarshal(dataV3, &rawV3); err != nil {
		t.Fatalf("unmarshal v3: %v", err)
	}
	var tagV3 string
	if err := json.Unmarshal(rawV3[0], &tagV3); err != nil {
		t.Fatalf("tag v3: %v", err)
	}
	if tagV3 != "DecimalLiteral" {
		t.Fatalf("expected v3 tag 'DecimalLiteral', got %q", tagV3)
	}
}

func TestLiteralDecodeRejectsWrongVersion(t *testing.T) {
	lit := ir.NewWholeNumberLiteral(7)

	dataV3, err := EncodeLiteral(Options{FormatVersion: FormatV3}, lit)
	if err != nil {
		t.Fatalf("EncodeLiteral(v3): %v", err)
	}
	if _, err := DecodeLiteral(Options{FormatVersion: FormatV1}, dataV3); err == nil {
		t.Fatalf("expected v1 decode to fail on v3 payload")
	}
}
