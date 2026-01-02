package ir

import (
	"bytes"
	"encoding/json"
	"fmt"
	"regexp"
	"strings"
	"unicode"
	"unicode/utf8"
)

// Name represents a Morphir IR Name.
//
// JSON encoding (Morphir-compatible): a Name is encoded as a JSON array of strings,
// for example: ["local","name"].
//
// This type implements encoding/json's hook methods MarshalJSON and UnmarshalJSON
// to provide custom marshalling/unmarshalling that matches the Morphir IR schemas.
//
// Note: We keep the underlying slice unexported to preserve immutability/value semantics.
// Use NameFromParts to construct and Parts() to retrieve a defensive copy.
type Name struct {
	parts []string
}

var nameWordPattern = regexp.MustCompile(`([a-zA-Z][a-z]*|[0-9]+)`) // Morphir-Elm compatible

// NameFromString translates a string into a Name by splitting it into words.
//
// This follows morphir-elm's Morphir.IR.Name.fromString behavior:
// - consecutive letters/digits form words
// - uppercase letters start new words
// - non-alphanumeric characters are treated as separators
// - extracted words are normalized to lowercase
func NameFromString(s string) Name {
	matches := nameWordPattern.FindAllString(s, -1)
	if len(matches) == 0 {
		return Name{parts: nil}
	}
	parts := make([]string, 0, len(matches))
	for _, m := range matches {
		parts = append(parts, strings.ToLower(m))
	}
	return NameFromParts(parts)
}

// NameFromParts constructs a Name from its component parts.
// The input slice is defensively copied.
func NameFromParts(parts []string) Name {
	if len(parts) == 0 {
		return Name{parts: nil}
	}
	copyParts := make([]string, len(parts))
	copy(copyParts, parts)
	return Name{parts: copyParts}
}

// Parts returns a defensive copy of the name parts.
func (n Name) Parts() []string {
	if len(n.parts) == 0 {
		return nil
	}
	copyParts := make([]string, len(n.parts))
	copy(copyParts, n.parts)
	return copyParts
}

// Equal performs structural equality.
func (n Name) Equal(other Name) bool {
	if len(n.parts) != len(other.parts) {
		return false
	}
	for i := range n.parts {
		if n.parts[i] != other.parts[i] {
			return false
		}
	}
	return true
}

// ToTitleCase turns a Name into a title-case string.
// Example: ["value","in","u","s","d"] -> "ValueInUSD".
func (n Name) ToTitleCase() string {
	if len(n.parts) == 0 {
		return ""
	}
	var b strings.Builder
	for _, w := range n.parts {
		b.WriteString(capitalize(w))
	}
	return b.String()
}

// ToCamelCase turns a Name into a camel-case string.
// Example: ["value","in","u","s","d"] -> "valueInUSD".
func (n Name) ToCamelCase() string {
	if len(n.parts) == 0 {
		return ""
	}
	if len(n.parts) == 1 {
		return n.parts[0]
	}
	var b strings.Builder
	b.WriteString(n.parts[0])
	for _, w := range n.parts[1:] {
		b.WriteString(capitalize(w))
	}
	return b.String()
}

// ToHumanWords turns a Name into a slice of human-readable words.
// The only difference from Parts() is how abbreviations are handled:
// any series of single-letter words is turned into a single uppercase word.
// Example: ["value","in","u","s","d"] -> ["value","in","USD"].
func (n Name) ToHumanWords() []string {
	words := n.parts
	if len(words) == 0 {
		return nil
	}
	if len(words) == 1 {
		// Match morphir-elm: preserve a single-letter name as-is.
		if utf8.RuneCountInString(words[0]) == 1 {
			return []string{words[0]}
		}
		return []string{words[0]}
	}

	joinAbbrev := func(abbrev []string) string {
		return strings.ToUpper(strings.Join(abbrev, ""))
	}

	prefix := make([]string, 0, len(words))
	abbrev := make([]string, 0, len(words))
	for _, w := range words {
		if utf8.RuneCountInString(w) == 1 {
			abbrev = append(abbrev, w)
			continue
		}

		if len(abbrev) == 0 {
			prefix = append(prefix, w)
			continue
		}

		prefix = append(prefix, joinAbbrev(abbrev), w)
		abbrev = abbrev[:0]
	}

	if len(abbrev) != 0 {
		prefix = append(prefix, joinAbbrev(abbrev))
	}
	return prefix
}

// ToHumanWordsTitle turns a Name into human-readable words with the first word capitalized.
func (n Name) ToHumanWordsTitle() []string {
	words := n.ToHumanWords()
	if len(words) == 0 {
		return nil
	}
	copyWords := make([]string, len(words))
	copy(copyWords, words)
	copyWords[0] = capitalize(copyWords[0])
	return copyWords
}

// ToSnakeCase turns a Name into a snake-case string.
// Example: ["value","in","u","s","d"] -> "value_in_USD".
func (n Name) ToSnakeCase() string {
	return strings.Join(n.ToHumanWords(), "_")
}

func capitalize(s string) string {
	if s == "" {
		return s
	}
	r, size := utf8.DecodeRuneInString(s)
	if r == utf8.RuneError && size == 0 {
		return s
	}
	return string(unicode.ToUpper(r)) + s[size:]
}

// MarshalJSON implements encoding/json.Marshaler.
// It encodes the name as a JSON array of strings.
func (n Name) MarshalJSON() ([]byte, error) {
	return json.Marshal(n.parts)
}

// UnmarshalJSON implements encoding/json.Unmarshaler.
// It decodes the name from a JSON array of strings.
func (n *Name) UnmarshalJSON(data []byte) error {
	if n == nil {
		return fmt.Errorf("ir.Name: UnmarshalJSON on nil receiver")
	}

	trimmed := bytes.TrimSpace(data)
	if bytes.Equal(trimmed, []byte("null")) {
		return fmt.Errorf("ir.Name: expected array of strings, got null")
	}

	var parts []string
	if err := json.Unmarshal(trimmed, &parts); err != nil {
		return fmt.Errorf("ir.Name: expected array of strings: %w", err)
	}

	// Defensive copy to prevent retaining references from json internals.
	*n = NameFromParts(parts)
	return nil
}
