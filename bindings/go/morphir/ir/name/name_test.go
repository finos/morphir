package name

import (
	"fmt"
	"testing"
)

func TestName_FromString(t *testing.T) {
	testCases := []struct {
		input    string
		expected Name
	}{
		{"fooBar_baz 123", Name{"foo", "bar", "baz", "123"}},
		{"valueInUSD", Name{"value", "in", "u", "s", "d"}},
		{"ValueInUSD", Name{"value", "in", "u", "s", "d"}},
		{"_-%", Name{}},
	}

	for _, tc := range testCases {
		name := fmt.Sprintf(`Given:"%v"`, tc.input)
		t.Run(name, func(t *testing.T) {
			actual := FromString(tc.input)
			if !actual.Equal(tc.expected) {
				t.Errorf("FromString(%s): expected %v, actual was %v", tc.input, tc.expected, actual)
			}
		})
	}
}

func TestName_ToCamelCase(t *testing.T) {
	testCases := []struct {
		input    Name
		expected string
	}{
		{Name{"foo", "bar", "baz", "123"}, "fooBarBaz123"},
		{Name{"value", "in", "u", "s", "d"}, "valueInUSD"},
	}

	for _, tc := range testCases {
		name := fmt.Sprintf(`Given:"%v"`, tc.input)
		t.Run(name, func(t *testing.T) {
			actual := tc.input.ToCamelCase()
			if actual != tc.expected {
				t.Errorf("ToCamelCase(%v): expected %s, actual %s", tc.input, tc.expected, actual)
			}
		})
	}
}

func TestName_ToTitleCase(t *testing.T) {
	testCases := []struct {
		input    Name
		expected string
	}{
		{Name{"foo", "bar", "baz", "123"}, "FooBarBaz123"},
		{Name{"value", "in", "u", "s", "d"}, "ValueInUSD"},
	}

	for _, tc := range testCases {
		name := fmt.Sprintf(`Given:"%v"`, tc.input)
		t.Run(name, func(t *testing.T) {
			actual := tc.input.ToTitleCase()
			if actual != tc.expected {
				t.Errorf("ToTitleCase(%v): expected %s, actual %s", tc.input, tc.expected, actual)
			}
		})
	}
}

func TestName_MarshalJSON(t *testing.T) {
	testCases := []struct {
		input    Name
		expected string
	}{
		{FromString("ToString"), `["to","string"]`},
		{Name{"foo", "bar", "baz", "123"}, `["foo","bar","baz","123"]`},
	}

	for _, tc := range testCases {
		name := fmt.Sprintf(`Given:"%v"`, tc.input)
		t.Run(name, func(t *testing.T) {
			actual, err := tc.input.MarshalJSON()
			if err != nil {
				t.Errorf("Error marshalling JSON: %v", err)
			}
			if string(actual) != tc.expected {
				t.Errorf("MarshalJSON(%v): expected %s, actual %s", tc.input, tc.expected, actual)
			}
		})
	}
}
