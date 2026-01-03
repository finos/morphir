package ir

import (
	"encoding/json"
	"testing"
)

func TestNameFromPartsCopiesInput(t *testing.T) {
	parts := []string{"local", "name"}
	name := NameFromParts(parts)

	parts[0] = "mutated"
	got := name.Parts()
	if len(got) != 2 || got[0] != "local" || got[1] != "name" {
		t.Fatalf("expected Name to be independent of input slice; got %#v", got)
	}

	got[0] = "mutated2"
	again := name.Parts()
	if again[0] != "local" {
		t.Fatalf("expected Parts() to return a copy; got %#v", again)
	}
}

func TestNameJSONRoundTrip(t *testing.T) {
	original := NameFromParts([]string{"Amazing", "Local", "Name"})

	data, err := json.Marshal(original)
	if err != nil {
		t.Fatalf("marshal: %v", err)
	}

	var decoded Name
	if err := json.Unmarshal(data, &decoded); err != nil {
		t.Fatalf("unmarshal: %v", err)
	}

	if !original.Equal(decoded) {
		t.Fatalf("expected roundtrip equality; original=%v decoded=%v", original.Parts(), decoded.Parts())
	}
}

func TestNameUnmarshalRejectsNonStringElements(t *testing.T) {
	var n Name
	err := json.Unmarshal([]byte(`["ok", 1]`), &n)
	if err == nil {
		t.Fatal(expectedError)
	}
}

func TestNameUnmarshalRejectsNonArray(t *testing.T) {
	var n Name
	err := json.Unmarshal([]byte(`{"not":"an array"}`), &n)
	if err == nil {
		t.Fatal(expectedError)
	}
}

func TestNameFromStringSplitsWordsMorphirStyle(t *testing.T) {
	name := NameFromString("fooBar_baz 123")
	if want := NameFromParts([]string{"foo", "bar", "baz", "123"}); !name.Equal(want) {
		t.Fatalf("expected %v, got %v", want.Parts(), name.Parts())
	}

	name = NameFromString("valueInUSD")
	if want := NameFromParts([]string{"value", "in", "u", "s", "d"}); !name.Equal(want) {
		t.Fatalf("expected %v, got %v", want.Parts(), name.Parts())
	}

	name = NameFromString("value_in_USD")
	if want := NameFromParts([]string{"value", "in", "u", "s", "d"}); !name.Equal(want) {
		t.Fatalf("expected %v, got %v", want.Parts(), name.Parts())
	}

	name = NameFromString("_-%")
	if len(name.Parts()) != 0 {
		t.Fatalf("expected empty name, got %v", name.Parts())
	}
}

func TestNameStringFormats(t *testing.T) {
	name := NameFromParts([]string{"foo", "bar", "baz", "123"})
	if got, want := name.ToTitleCase(), "FooBarBaz123"; got != want {
		t.Fatalf("ToTitleCase: want %q, got %q", want, got)
	}
	if got, want := name.ToCamelCase(), "fooBarBaz123"; got != want {
		t.Fatalf("ToCamelCase: want %q, got %q", want, got)
	}
	if got, want := name.ToSnakeCase(), "foo_bar_baz_123"; got != want {
		t.Fatalf("ToSnakeCase: want %q, got %q", want, got)
	}

	abbrev := NameFromParts([]string{"value", "in", "u", "s", "d"})
	if got, want := abbrev.ToTitleCase(), "ValueInUSD"; got != want {
		t.Fatalf("ToTitleCase(abbrev): want %q, got %q", want, got)
	}
	if got, want := abbrev.ToCamelCase(), "valueInUSD"; got != want {
		t.Fatalf("ToCamelCase(abbrev): want %q, got %q", want, got)
	}
	if got, want := abbrev.ToSnakeCase(), "value_in_USD"; got != want {
		t.Fatalf("ToSnakeCase(abbrev): want %q, got %q", want, got)
	}

	words := abbrev.ToHumanWords()
	if len(words) != 3 || words[0] != "value" || words[1] != "in" || words[2] != "USD" {
		t.Fatalf("ToHumanWords(abbrev): got %#v", words)
	}
	wordsTitle := abbrev.ToHumanWordsTitle()
	if len(wordsTitle) != 3 || wordsTitle[0] != "Value" || wordsTitle[1] != "in" || wordsTitle[2] != "USD" {
		t.Fatalf("ToHumanWordsTitle(abbrev): got %#v", wordsTitle)
	}
}
