package string

import (
	"github.com/finos/morphir/bindings/go/morphir/sdk/basics"
	"strings"
)

type String string

func IsEmpty[Str ~string](s Str) basics.Bool {
	return len(s) == 0
}

func Length[Str ~string](s Str) basics.Int {
	return basics.Int(len(s))
}

// Reverse reverses the characters in a string
func Reverse[Str ~string](s Str) String {
	runes := []rune(s)
	for i, j := 0, len(runes)-1; i < j; i, j = i+1, j-1 {
		runes[i], runes[j] = runes[j], runes[i]
	}
	return String(string(runes))
}

func ToUpper[Str ~string](s Str) String {
	return String(strings.ToUpper(string(s)))
}

func (s String) Reverse() String {
	return Reverse(s)
}
