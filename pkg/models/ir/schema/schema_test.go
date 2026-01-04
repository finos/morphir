package schema

import (
	"strings"
	"testing"
)

func TestGetSchema(t *testing.T) {
	tests := []struct {
		name        string
		version     Version
		wantErr     bool
		wantContain string
	}{
		{
			name:        "V1 schema",
			version:     V1,
			wantErr:     false,
			wantContain: "formatVersion",
		},
		{
			name:        "V2 schema",
			version:     V2,
			wantErr:     false,
			wantContain: "formatVersion",
		},
		{
			name:        "V3 schema",
			version:     V3,
			wantErr:     false,
			wantContain: "formatVersion",
		},
		{
			name:    "unsupported version",
			version: Version(99),
			wantErr: true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got, err := GetSchema(tt.version)
			if (err != nil) != tt.wantErr {
				t.Errorf("GetSchema() error = %v, wantErr %v", err, tt.wantErr)
				return
			}
			if !tt.wantErr && !strings.Contains(string(got), tt.wantContain) {
				t.Errorf("GetSchema() result does not contain %q", tt.wantContain)
			}
		})
	}
}

func TestGetSchemaVersions(t *testing.T) {
	t.Run("GetSchemaV1", func(t *testing.T) {
		data, err := GetSchemaV1()
		if err != nil {
			t.Fatalf("GetSchemaV1() error = %v", err)
		}
		if !strings.Contains(string(data), `const: 1`) {
			t.Error("V1 schema should contain 'const: 1' for formatVersion")
		}
	})

	t.Run("GetSchemaV2", func(t *testing.T) {
		data, err := GetSchemaV2()
		if err != nil {
			t.Fatalf("GetSchemaV2() error = %v", err)
		}
		if !strings.Contains(string(data), `const: 2`) {
			t.Error("V2 schema should contain 'const: 2' for formatVersion")
		}
	})

	t.Run("GetSchemaV3", func(t *testing.T) {
		data, err := GetSchemaV3()
		if err != nil {
			t.Fatalf("GetSchemaV3() error = %v", err)
		}
		if !strings.Contains(string(data), `const: 3`) {
			t.Error("V3 schema should contain 'const: 3' for formatVersion")
		}
	})
}

func TestLatestVersion(t *testing.T) {
	if LatestVersion() != V3 {
		t.Errorf("LatestVersion() = %v, want V3", LatestVersion())
	}
}

func TestSupportedVersions(t *testing.T) {
	versions := SupportedVersions()
	if len(versions) != 3 {
		t.Errorf("SupportedVersions() returned %d versions, want 3", len(versions))
	}

	expected := []Version{V1, V2, V3}
	for i, v := range expected {
		if versions[i] != v {
			t.Errorf("SupportedVersions()[%d] = %v, want %v", i, versions[i], v)
		}
	}
}

func TestGetLatestSchema(t *testing.T) {
	data, err := GetLatestSchema()
	if err != nil {
		t.Fatalf("GetLatestSchema() error = %v", err)
	}
	if !strings.Contains(string(data), `const: 3`) {
		t.Error("Latest schema should be V3 and contain 'const: 3'")
	}
}

func TestVersionString(t *testing.T) {
	tests := []struct {
		version Version
		want    string
	}{
		{V1, "v1"},
		{V2, "v2"},
		{V3, "v3"},
	}

	for _, tt := range tests {
		t.Run(tt.want, func(t *testing.T) {
			if got := tt.version.String(); got != tt.want {
				t.Errorf("Version.String() = %v, want %v", got, tt.want)
			}
		})
	}
}
