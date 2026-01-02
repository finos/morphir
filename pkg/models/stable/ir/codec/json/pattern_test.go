package json

import (
	"encoding/json"
	"testing"

	ir "github.com/finos/morphir-go/pkg/models/stable/ir"
)

func TestPatternRoundTripV3(t *testing.T) {
	opts := Options{FormatVersion: FormatV3}

	usd := ir.NameFromParts([]string{"usd"})
	my := ir.NameFromParts([]string{"my"})
	mod := ir.PathFromParts([]ir.Name{my, ir.NameFromParts([]string{"mod"})})
	pkg := ir.PathFromParts([]ir.Name{my, ir.NameFromParts([]string{"pkg"})})
	fq := ir.FQNameFromParts(pkg, mod, ir.NameFromParts([]string{"ctor"}))

	pat := ir.NewAsPattern(unitAttr{},
		ir.NewConstructorPattern(unitAttr{}, fq, []ir.Pattern[unitAttr]{
			ir.NewTuplePattern(unitAttr{}, []ir.Pattern[unitAttr]{
				ir.NewWildcardPattern(unitAttr{}),
				ir.NewUnitPattern(unitAttr{}),
			}),
			ir.NewHeadTailPattern(unitAttr{},
				ir.NewLiteralPattern(unitAttr{}, ir.NewWholeNumberLiteral(123)),
				ir.NewEmptyListPattern(unitAttr{}),
			),
			ir.NewLiteralPattern(unitAttr{}, ir.NewStringLiteral("valueInUSD")),
		}),
		usd,
	)

	data, err := EncodePattern(opts, encodeUnitAttr, pat)
	if err != nil {
		t.Fatalf("EncodePattern: %v", err)
	}

	decoded, err := DecodePattern(opts, decodeUnitAttr, data)
	if err != nil {
		t.Fatalf("DecodePattern: %v", err)
	}

	if !ir.EqualPattern(func(unitAttr, unitAttr) bool { return true }, pat, decoded) {
		t.Fatalf("expected structural equality after roundtrip")
	}
}

func TestPatternVersionedTags(t *testing.T) {
	pat := ir.NewWildcardPattern(unitAttr{})

	dataV1, err := EncodePattern(Options{FormatVersion: FormatV1}, encodeUnitAttr, pat)
	if err != nil {
		t.Fatalf("EncodePattern(v1): %v", err)
	}
	var rawV1 []json.RawMessage
	if err := json.Unmarshal(dataV1, &rawV1); err != nil {
		t.Fatalf("unmarshal v1: %v", err)
	}
	var tagV1 string
	if err := json.Unmarshal(rawV1[0], &tagV1); err != nil {
		t.Fatalf("tag v1: %v", err)
	}
	if tagV1 != "wildcard_pattern" {
		t.Fatalf("expected v1 tag 'wildcard_pattern', got %q", tagV1)
	}

	dataV3, err := EncodePattern(Options{FormatVersion: FormatV3}, encodeUnitAttr, pat)
	if err != nil {
		t.Fatalf("EncodePattern(v3): %v", err)
	}
	var rawV3 []json.RawMessage
	if err := json.Unmarshal(dataV3, &rawV3); err != nil {
		t.Fatalf("unmarshal v3: %v", err)
	}
	var tagV3 string
	if err := json.Unmarshal(rawV3[0], &tagV3); err != nil {
		t.Fatalf("tag v3: %v", err)
	}
	if tagV3 != "WildcardPattern" {
		t.Fatalf("expected v3 tag 'WildcardPattern', got %q", tagV3)
	}
}

func TestPatternDecodeRejectsWrongVersion(t *testing.T) {
	pat := ir.NewHeadTailPattern(unitAttr{}, ir.NewWildcardPattern(unitAttr{}), ir.NewEmptyListPattern(unitAttr{}))

	dataV3, err := EncodePattern(Options{FormatVersion: FormatV3}, encodeUnitAttr, pat)
	if err != nil {
		t.Fatalf("EncodePattern(v3): %v", err)
	}

	if _, err := DecodePattern(Options{FormatVersion: FormatV1}, decodeUnitAttr, dataV3); err == nil {
		t.Fatalf("expected v1 decode to fail on v3 payload")
	}
}
