package ir

import (
	"encoding/json"
	"testing"
)

func TestFQNameJSONRoundTrip(t *testing.T) {
	original := FQNameFromParts(
		PathFromParts([]Name{NameFromParts([]string{"Excellent"}), NameFromParts([]string{"Package"})}),
		PathFromParts([]Name{NameFromParts([]string{"Fantastic"}), NameFromParts([]string{"Module"})}),
		NameFromParts([]string{"Amazing", "Local", "Name"}),
	)

	data, err := json.Marshal(original)
	if err != nil {
		t.Fatalf("marshal: %v", err)
	}

	var decoded FQName
	if err := json.Unmarshal(data, &decoded); err != nil {
		t.Fatalf("unmarshal: %v", err)
	}

	if !original.Equal(decoded) {
		pp1, mp1, ln1 := original.Parts()
		pp2, mp2, ln2 := decoded.Parts()
		t.Fatalf(
			"expected roundtrip equality; original=(%v,%v,%v) decoded=(%v,%v,%v)",
			pp1.Parts(), mp1.Parts(), ln1.Parts(),
			pp2.Parts(), mp2.Parts(), ln2.Parts(),
		)
	}
}

func TestFQNameUnmarshalRejectsWrongLength(t *testing.T) {
	var f FQName
	if err := json.Unmarshal([]byte(`[]`), &f); err == nil {
		t.Fatal(expectedError)
	}
	if err := json.Unmarshal([]byte(`[[],[]]`), &f); err == nil {
		t.Fatal(expectedError)
	}
	if err := json.Unmarshal([]byte(`[[],[],[],[]]`), &f); err == nil {
		t.Fatal(expectedError)
	}
}

func TestFQNameUnmarshalRejectsInvalidParts(t *testing.T) {
	var f FQName
	if err := json.Unmarshal([]byte(`[{"bad":true}, [], []]`), &f); err == nil {
		t.Fatal(expectedError)
	}
	if err := json.Unmarshal([]byte(`[[], {"bad":true}, []]`), &f); err == nil {
		t.Fatal(expectedError)
	}
	if err := json.Unmarshal([]byte(`[[], [], {"bad":true}]`), &f); err == nil {
		t.Fatal(expectedError)
	}
}

func TestFQNameStringAndParseRoundTrip(t *testing.T) {
	f := FQNameFromParts(
		PathFromParts([]Name{NameFromParts([]string{"foo", "bar"})}),
		PathFromParts([]Name{NameFromParts([]string{"baz"})}),
		NameFromParts([]string{"a", "name"}),
	)

	if got, want := f.String(), "FooBar:Baz:aName"; got != want {
		t.Fatalf("want %q, got %q", want, got)
	}

	parsed, err := ParseFQName("FooBar:Baz:aName")
	if err != nil {
		t.Fatalf("ParseFQName: %v", err)
	}
	if !parsed.Equal(f) {
		pp1, mp1, ln1 := f.Parts()
		pp2, mp2, ln2 := parsed.Parts()
		t.Fatalf("expected equality; original=(%v,%v,%v) parsed=(%v,%v,%v)", pp1.Parts(), mp1.Parts(), ln1.Parts(), pp2.Parts(), mp2.Parts(), ln2.Parts())
	}
}

func TestParseFQNameRejectsMalformedInput(t *testing.T) {
	if _, err := ParseFQName("no-separator"); err == nil {
		t.Fatal(expectedError)
	}
	if _, err := ParseFQName("a:b"); err == nil {
		t.Fatal(expectedError)
	}
	if _, err := ParseFQName("a:b:c:d"); err == nil {
		t.Fatal(expectedError)
	}
}
