package ir

import (
	"encoding/json"
	"testing"
)

func TestPathFromPartsCopiesInput(t *testing.T) {
	parts := []Name{NameFromParts([]string{"a"}), NameFromParts([]string{"b", "c"})}
	path := PathFromParts(parts)

	// Mutate caller slice.
	parts[0] = NameFromParts([]string{"mutated"})

	got := path.Parts()
	if len(got) != 2 {
		t.Fatalf("expected 2 parts; got %d", len(got))
	}
	if !got[0].Equal(NameFromParts([]string{"a"})) {
		t.Fatalf("expected first part to remain 'a'; got %#v", got[0].Parts())
	}

	// Mutate returned slice.
	got[0] = NameFromParts([]string{"mutated2"})
	again := path.Parts()
	if !again[0].Equal(NameFromParts([]string{"a"})) {
		t.Fatalf("expected Parts() to return a copy; got %#v", again[0].Parts())
	}
}

func TestPathJSONRoundTrip(t *testing.T) {
	original := PathFromParts([]Name{
		NameFromParts([]string{"Excellent"}),
		NameFromParts([]string{"Package"}),
	})

	data, err := json.Marshal(original)
	if err != nil {
		t.Fatalf("marshal: %v", err)
	}

	var decoded Path
	if err := json.Unmarshal(data, &decoded); err != nil {
		t.Fatalf("unmarshal: %v", err)
	}

	if !original.Equal(decoded) {
		t.Fatalf("expected roundtrip equality; original=%v decoded=%v", original.Parts(), decoded.Parts())
	}
}

func TestPathUnmarshalRejectsNonArray(t *testing.T) {
	var p Path
	err := json.Unmarshal([]byte(`{"not":"an array"}`), &p)
	if err == nil {
		t.Fatal(expectedError)
	}
}

func TestPathUnmarshalRejectsInvalidNameElement(t *testing.T) {
	var p Path
	// Each element must decode as a Name (i.e. array of strings)
	err := json.Unmarshal([]byte(`[ ["ok"], {"bad":true} ]`), &p)
	if err == nil {
		t.Fatal(expectedError)
	}
}

func TestPathFromStringSplitsMorphirStyle(t *testing.T) {
	p := PathFromString("fooBar.Baz")
	want := PathFromParts([]Name{NameFromParts([]string{"foo", "bar"}), NameFromParts([]string{"baz"})})
	if !p.Equal(want) {
		t.Fatalf("expected %v, got %v", want.Parts(), p.Parts())
	}

	p = PathFromString("foo bar/baz")
	want = PathFromParts([]Name{NameFromParts([]string{"foo", "bar"}), NameFromParts([]string{"baz"})})
	if !p.Equal(want) {
		t.Fatalf("expected %v, got %v", want.Parts(), p.Parts())
	}
}

func TestPathToStringUsesFormatterAndSeparator(t *testing.T) {
	path := PathFromParts([]Name{NameFromParts([]string{"foo", "bar"}), NameFromParts([]string{"baz"})})
	if got, want := path.ToString(func(n Name) string { return n.ToTitleCase() }, "."), "FooBar.Baz"; got != want {
		t.Fatalf("want %q, got %q", want, got)
	}
	if got, want := path.ToString(func(n Name) string { return n.ToSnakeCase() }, "/"), "foo_bar/baz"; got != want {
		t.Fatalf("want %q, got %q", want, got)
	}
}
