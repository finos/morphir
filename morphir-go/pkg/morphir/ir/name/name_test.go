package name

import "testing"

func TestName_FromString(t *testing.T) {
	testCases := []struct {
		name     string
		input    string
		expected Name
	}{
		{`Given "fooBar_baz 123"`, "fooBar_baz", Name{"foo", "bar", "baz", "123"}},
	}

	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			actual := FromString(tc.input)
			if actual.Equal(tc.expected) {
				t.Errorf("FromString(%s): expected %v, actual %v", tc.input, tc.expected, actual)
			}
		})
	}
}
