package basics

import "testing"

func TestAdd_For_Int(t *testing.T) {
	testCases := []struct {
		name     string
		a        Int
		b        Int
		expected Int
	}{
		{"3002 + 4004", 3002, 4004, 7006},
	}

	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			actual := Add(tc.a)(tc.b)
			if actual != tc.expected {
				t.Errorf("Add(%d): expected %d, actual %d", tc.a, tc.expected, actual)
			}
		})
	}
}

func TestAdd_For_Float(t *testing.T) {
	testCases := []struct {
		name     string
		a        Float
		b        Float
		expected Float
	}{
		{"3.14 + 3.14", 3.14, 3.14, 6.28},
	}

	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			actual := Add(tc.a)(tc.b)
			if actual != tc.expected {
				t.Errorf("Add(%f): expected %f, actual %f", tc.a, tc.expected, actual)
			}
		})
	}
}

func TestSubtract_For_Int(t *testing.T) {
	testCases := []struct {
		name     string
		a        Int
		b        Int
		expected Int
	}{
		{"4-3", 4, 3, 1},
	}

	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			actual := Subtract(tc.a)(tc.b)
			if actual != tc.expected {
				t.Errorf("Subtract(%d): expected %d, actual %d", tc.a, tc.expected, actual)
			}
		})
	}
}
