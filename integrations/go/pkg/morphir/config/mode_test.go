package config

import (
	"testing"
)

func TestMode_IsEmptyOrUnspecified(t *testing.T) {
	testCases := []struct {
		name   string
		input  Mode
		expect bool
	}{
		{"Global", Global, false},
		{"Local", Local, false},
		{"Upwards", Upwards, false},
		{"Unspecified", Unspecified, true},
		{"UpwardsGlobal", UpwardsGlobal, false},
		{"Default", Default, false},
		{"Empty", 0, true},
		{"Global | Unspecified", Global | Unspecified, false},
	}

	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			actual := tc.input.IsEmptyOrUnspecified()
			if actual != tc.expect {
				t.Errorf("Expected %v to be empty or unspecified, but got %v", tc.input, actual)
			}
		})
	}
}

func TestMode_HasGlobal(t *testing.T) {
	testCases := []struct {
		name   string
		input  Mode
		expect bool
	}{
		{"Global", Global, true},
		{"UpwardsGlobal", UpwardsGlobal, true},
	}

	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			actual := tc.input.HasGlobal()
			if actual != tc.expect {
				t.Errorf("Expected %v to have Global, but got %v", tc.input, actual)
			}
		})
	}
}

func TestMode_HasLocal(t *testing.T) {
	mode := Local
	if !mode.HasLocal() {
		t.Errorf("Expected Mode to be Local")
	}
}

func TestMode_HasUpwards(t *testing.T) {
	mode := Upwards
	if !mode.HasUpwards() {
		t.Errorf("Expected Mode to be Upwards")
	}
}

func TestMode_HasUpwardsGlobal(t *testing.T) {
	mode := UpwardsGlobal
	if !mode.HasUpwardsGlobal() {
		t.Errorf("Expected Mode to be UpwardsGlobal")
	}
}

func TestMode_IsDefault(t *testing.T) {
	mode := Default
	if !mode.IsDefault() {
		t.Errorf("Expected Mode to be Default")
	}
}

func TestMode_Including(t *testing.T) {
	testCases := []struct {
		name      string
		original  Mode
		including Mode
		expected  Mode
	}{
		{"Global including Local", Global, Local, Global | Local},
		{"Local including Upwards", Local, Upwards, Local | Upwards},
		{"Upwards including Global", Upwards, Global, Upwards | Global},
		{"Upwards including UpwardsGlobal", Upwards, UpwardsGlobal, UpwardsGlobal},
		{"UpwardsGlobal including Default", UpwardsGlobal, Default, UpwardsGlobal},
	}
	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			actual := tc.original.Including(tc.including)
			if actual != tc.expected {
				t.Errorf("Original mode was %v and we are including %v, expected %v but got %v", tc.original, tc.including, tc.expected, actual)
			}
		})
	}
}

func TestMode_ShouldApplyDefaults(t *testing.T) {
	testCases := []struct {
		name     string
		original Mode
		expected bool
	}{
		{"Global", Global, false},
		{"Local", Local, false},
		{"Upwards", Upwards, false},
		{"UpwardsGlobal", UpwardsGlobal, false},
		{"Default", Default, false},
		{"Empty", 0, true},
		{"Unspecified", Unspecified, true},
		{"Global | Unspecified", Global | Unspecified, false},
	}

	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			actual := tc.original.ShouldApplyDefaults()
			if actual != tc.expected {
				t.Errorf("Expected %v to return %v, but got %v", tc.original, tc.expected, actual)
			}
		})
	}
}
