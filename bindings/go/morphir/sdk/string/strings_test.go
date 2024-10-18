package string

import (
	"fmt"
	"testing"
)

func TestString_Reverse(t *testing.T) {
	testCases := []struct {
		input    String
		expected String
	}{
		{"fooBar_baz 123", "321 zab_raBoof"},
		{"valueInUSD", "DSUnIeulav"},
		{"ValueInUSD", "DSUnIeulaV"},
		{"_-%", "%-_"},
	}

	for _, tc := range testCases {
		name := fmt.Sprintf(`Given:"%v"`, tc.input)
		t.Run(name, func(t *testing.T) {
			actual := tc.input.Reverse()
			if actual != tc.expected {
				t.Errorf("Reverse(%v): expected %s, actual %s", tc.input, tc.expected, actual)
			}
		})
	}
}
