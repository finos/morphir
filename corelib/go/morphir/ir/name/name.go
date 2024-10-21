package name

import (
	"github.com/finos/morphir/corelib/go/morphir/sdk/list"
	"regexp"
	"strings"

	"github.com/life4/genesis/slices"
	"golang.org/x/text/cases"
	"golang.org/x/text/language"
)

var wordPattern = regexp.MustCompile("[a-zA-Z][a-z]*|[0-9]+")

type Name []string

func FromString(s string) Name {
	words := wordPattern.FindAllString(s, -1)
	words = slices.Map(words, strings.ToLower)
	return FromList(words)
}

func FromList(words []string) Name {
	return words
}

func ToCamelCase(n Name) string {
	if len(n) == 0 {
		return ""
	}
	head := n[:1]
	tail := slices.Map(n[1:], capitalize)
	s := append(head, tail...)
	return strings.Join(s, "")
}

func ToTitleCase(n Name) string {
	return strings.Join(slices.Map(n, toTitleCase), "")
}

func ToList(n Name) list.List[string] {
	return list.FromSlice(n)
}

func (n Name) ToList() list.List[string] {
	return list.FromSlice(n)
}

func (n Name) ToCamelCase() string {
	return ToCamelCase(n)
}

func (n Name) ToTitleCase() string {
	return ToTitleCase(n)
}

func (n Name) Equal(other Name) bool {
	return slices.Equal(n, other)
}

func capitalize(s string) string {
	if len(s) == 0 {
		return s
	}
	return strings.ToUpper(s[:1]) + s[1:]
}

func toTitleCase(s string) string {
	return cases.Title(language.English, cases.Compact).String(s)
}
