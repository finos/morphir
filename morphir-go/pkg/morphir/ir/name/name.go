package name

import (
	"regexp"
	"strings"

	"github.com/life4/genesis/slices"
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

func (n Name) ToList() []string {
	return n
}

func (n Name) Equal(other Name) bool {
	return slices.Equal(n, other)
}
