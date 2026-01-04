package configloader

import (
	"testing"
)

func TestDefaultValuesReturnsExpectedStructure(t *testing.T) {
	defaults := DefaultValues()

	if defaults == nil {
		t.Fatal("DefaultValues returned nil")
	}

	// Check top-level sections exist
	sections := []string{"morphir", "workspace", "ir", "codegen", "cache", "logging", "ui"}
	for _, section := range sections {
		if _, ok := defaults[section]; !ok {
			t.Errorf("missing section: %s", section)
		}
	}
}

func TestDefaultValuesIRSection(t *testing.T) {
	defaults := DefaultValues()
	ir := defaults["ir"].(map[string]any)

	if ir["format_version"] != int64(3) {
		t.Errorf("ir.format_version: want 3, got %v", ir["format_version"])
	}
	if ir["strict_mode"] != false {
		t.Errorf("ir.strict_mode: want false, got %v", ir["strict_mode"])
	}
}

func TestDefaultValuesWorkspaceSection(t *testing.T) {
	defaults := DefaultValues()
	workspace := defaults["workspace"].(map[string]any)

	if workspace["output_dir"] != ".morphir" {
		t.Errorf("workspace.output_dir: want .morphir, got %v", workspace["output_dir"])
	}
}

func TestDefaultValuesLoggingSection(t *testing.T) {
	defaults := DefaultValues()
	logging := defaults["logging"].(map[string]any)

	if logging["level"] != "info" {
		t.Errorf("logging.level: want info, got %v", logging["level"])
	}
	if logging["format"] != "text" {
		t.Errorf("logging.format: want text, got %v", logging["format"])
	}
}

func TestDefaultValuesUISection(t *testing.T) {
	defaults := DefaultValues()
	ui := defaults["ui"].(map[string]any)

	if ui["color"] != true {
		t.Errorf("ui.color: want true, got %v", ui["color"])
	}
	if ui["interactive"] != true {
		t.Errorf("ui.interactive: want true, got %v", ui["interactive"])
	}
	if ui["theme"] != "default" {
		t.Errorf("ui.theme: want default, got %v", ui["theme"])
	}
}

func TestGetString(t *testing.T) {
	m := map[string]any{
		"section": map[string]any{
			"key": "value",
		},
	}

	got := GetString(m, "section.key", "default")
	if got != "value" {
		t.Errorf("GetString: want value, got %q", got)
	}

	got = GetString(m, "missing.key", "default")
	if got != "default" {
		t.Errorf("GetString missing: want default, got %q", got)
	}

	got = GetString(nil, "any.path", "default")
	if got != "default" {
		t.Errorf("GetString nil map: want default, got %q", got)
	}
}

func TestGetInt(t *testing.T) {
	m := map[string]any{
		"section": map[string]any{
			"intVal":   42,
			"int64Val": int64(100),
			"floatVal": 3.14,
		},
	}

	if got := GetInt(m, "section.intVal", 0); got != 42 {
		t.Errorf("GetInt int: want 42, got %d", got)
	}

	if got := GetInt(m, "section.int64Val", 0); got != 100 {
		t.Errorf("GetInt int64: want 100, got %d", got)
	}

	if got := GetInt(m, "section.floatVal", 0); got != 3 {
		t.Errorf("GetInt float: want 3, got %d", got)
	}

	if got := GetInt(m, "missing", 99); got != 99 {
		t.Errorf("GetInt missing: want 99, got %d", got)
	}
}

func TestGetInt64(t *testing.T) {
	m := map[string]any{
		"section": map[string]any{
			"val": int64(9223372036854775807),
		},
	}

	got := GetInt64(m, "section.val", 0)
	if got != 9223372036854775807 {
		t.Errorf("GetInt64: want max int64, got %d", got)
	}

	got = GetInt64(m, "missing", 42)
	if got != 42 {
		t.Errorf("GetInt64 missing: want 42, got %d", got)
	}
}

func TestGetBool(t *testing.T) {
	m := map[string]any{
		"section": map[string]any{
			"enabled": true,
		},
	}

	got := GetBool(m, "section.enabled", false)
	if got != true {
		t.Errorf("GetBool: want true, got %t", got)
	}

	got = GetBool(m, "missing", true)
	if got != true {
		t.Errorf("GetBool missing: want true, got %t", got)
	}
}

func TestGetStringSlice(t *testing.T) {
	m := map[string]any{
		"targets": []string{"go", "scala"},
	}

	got := GetStringSlice(m, "targets", nil)
	if len(got) != 2 || got[0] != "go" || got[1] != "scala" {
		t.Errorf("GetStringSlice: want [go scala], got %v", got)
	}

	// Test with []any
	m2 := map[string]any{
		"targets": []any{"typescript", "python"},
	}
	got = GetStringSlice(m2, "targets", nil)
	if len(got) != 2 || got[0] != "typescript" || got[1] != "python" {
		t.Errorf("GetStringSlice []any: want [typescript python], got %v", got)
	}

	got = GetStringSlice(m, "missing", []string{"default"})
	if len(got) != 1 || got[0] != "default" {
		t.Errorf("GetStringSlice missing: want [default], got %v", got)
	}
}

func TestGetStringSliceDefensiveCopy(t *testing.T) {
	m := map[string]any{
		"targets": []string{"go", "scala"},
	}

	got := GetStringSlice(m, "targets", nil)
	got[0] = "modified"

	// Original should be unchanged
	original := m["targets"].([]string)
	if original[0] != "go" {
		t.Errorf("GetStringSlice should return a copy, original was modified")
	}
}

func TestSplitPath(t *testing.T) {
	tests := []struct {
		input string
		want  []string
	}{
		{"", nil},
		{"simple", []string{"simple"}},
		{"one.two", []string{"one", "two"}},
		{"a.b.c.d", []string{"a", "b", "c", "d"}},
	}

	for _, tt := range tests {
		got := splitPath(tt.input)
		if len(got) != len(tt.want) {
			t.Errorf("splitPath(%q): want %v, got %v", tt.input, tt.want, got)
			continue
		}
		for i := range got {
			if got[i] != tt.want[i] {
				t.Errorf("splitPath(%q)[%d]: want %q, got %q", tt.input, i, tt.want[i], got[i])
			}
		}
	}
}

func TestGetNestedValue(t *testing.T) {
	m := map[string]any{
		"level1": map[string]any{
			"level2": map[string]any{
				"level3": "deep value",
			},
		},
	}

	got := getNestedValue(m, "level1.level2.level3")
	if got != "deep value" {
		t.Errorf("getNestedValue: want 'deep value', got %v", got)
	}

	got = getNestedValue(m, "level1.missing.level3")
	if got != nil {
		t.Errorf("getNestedValue missing: want nil, got %v", got)
	}

	got = getNestedValue(nil, "any.path")
	if got != nil {
		t.Errorf("getNestedValue nil map: want nil, got %v", got)
	}

	got = getNestedValue(m, "")
	if got != nil {
		t.Errorf("getNestedValue empty path: want nil, got %v", got)
	}
}
