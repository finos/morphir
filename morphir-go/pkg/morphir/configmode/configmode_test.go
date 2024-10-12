package configmode

import "testing"

func TestConfigMode_IsGlobal(t *testing.T) {
	mode := Global
	if !mode.IsGlobal() {
		t.Errorf("Expected ConfigMode to be Global")
	}
}

func TestConfigMode_IsLocal(t *testing.T) {
	mode := Local
	if !mode.IsLocal() {
		t.Errorf("Expected ConfigMode to be Local")
	}
}

func TestConfigMode_IsUpwards(t *testing.T) {
	mode := Upwards
	if !mode.IsUpwards() {
		t.Errorf("Expected ConfigMode to be Upwards")
	}
}

func TestConfigMode_IsUpwardsGlobal(t *testing.T) {
	mode := UpwardsGlobal
	if !mode.IsUpwardsGlobal() {
		t.Errorf("Expected ConfigMode to be UpwardsGlobal")
	}
}

func TestConfigMode_IsDefault(t *testing.T) {
	mode := Default
	if !mode.IsDefault() {
		t.Errorf("Expected ConfigMode to be Default")
	}
}

func TestConfigMode_Including(t *testing.T) {
	testCases := []struct {
		name      string
		original  ConfigMode
		including ConfigMode
		expected  ConfigMode
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
