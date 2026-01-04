package sources

import (
	"reflect"
	"testing"
	"time"
)

func TestEnvSourceName(t *testing.T) {
	src := NewEnvSource("MORPHIR", 6)

	if got := src.Name(); got != "env" {
		t.Errorf("Name: want env, got %q", got)
	}
}

func TestEnvSourcePriority(t *testing.T) {
	src := NewEnvSource("MORPHIR", 6)

	if got := src.Priority(); got != 6 {
		t.Errorf("Priority: want 6, got %d", got)
	}
}

func TestEnvSourcePath(t *testing.T) {
	src := NewEnvSource("MORPHIR", 6)

	if got := src.Path(); got != "MORPHIR_*" {
		t.Errorf("Path: want MORPHIR_*, got %q", got)
	}
}

func TestEnvSourceExistsAlwaysTrue(t *testing.T) {
	src := NewEnvSource("MORPHIR", 6)

	exists, err := src.Exists()
	if err != nil {
		t.Fatalf("Exists: unexpected error: %v", err)
	}
	if !exists {
		t.Error("Exists: want true, got false")
	}
}

func TestEnvSourceLoadSimpleValues(t *testing.T) {
	environ := func() []string {
		return []string{
			"MORPHIR_IR_FORMAT_VERSION=3",
			"MORPHIR_WORKSPACE_ROOT=/home/user/project",
			"MORPHIR_CACHE_ENABLED=true",
			"OTHER_VAR=ignored",
		}
	}

	src := newEnvSourceWithEnviron("MORPHIR", 6, environ)

	data, err := src.Load()
	if err != nil {
		t.Fatalf("Load: unexpected error: %v", err)
	}
	if data == nil {
		t.Fatal("Load: expected non-nil data")
	}

	// Check ir section
	ir, ok := data["ir_format_version"]
	if !ok {
		t.Fatal("Load: expected ir_format_version key")
	}
	if ir != int64(3) {
		t.Errorf("ir_format_version: want 3, got %v (type %T)", ir, ir)
	}

	// Check workspace section
	workspace, ok := data["workspace_root"]
	if !ok {
		t.Fatal("Load: expected workspace_root key")
	}
	if workspace != "/home/user/project" {
		t.Errorf("workspace_root: want /home/user/project, got %v", workspace)
	}

	// Check cache section
	cache, ok := data["cache_enabled"]
	if !ok {
		t.Fatal("Load: expected cache_enabled key")
	}
	if cache != true {
		t.Errorf("cache_enabled: want true, got %v", cache)
	}
}

func TestEnvSourceLoadNestedValues(t *testing.T) {
	environ := func() []string {
		return []string{
			"MORPHIR_CODEGEN__GO__PACKAGE=morphir",
			"MORPHIR_CODEGEN__GO__OPTIONS__USE_POINTERS=true",
			"MORPHIR_CODEGEN__SCALA__VERSION=2.13",
		}
	}

	src := newEnvSourceWithEnviron("MORPHIR", 6, environ)

	data, err := src.Load()
	if err != nil {
		t.Fatalf("Load: unexpected error: %v", err)
	}
	if data == nil {
		t.Fatal("Load: expected non-nil data")
	}

	// Navigate to codegen.go.package
	codegen, ok := data["codegen"].(map[string]any)
	if !ok {
		t.Fatal("Load: expected codegen to be a map")
	}

	goSection, ok := codegen["go"].(map[string]any)
	if !ok {
		t.Fatal("Load: expected codegen.go to be a map")
	}

	if goSection["package"] != "morphir" {
		t.Errorf("codegen.go.package: want morphir, got %v", goSection["package"])
	}

	// Check nested options
	options, ok := goSection["options"].(map[string]any)
	if !ok {
		t.Fatal("Load: expected codegen.go.options to be a map")
	}

	if options["use_pointers"] != true {
		t.Errorf("codegen.go.options.use_pointers: want true, got %v", options["use_pointers"])
	}

	// Check scala section
	scala, ok := codegen["scala"].(map[string]any)
	if !ok {
		t.Fatal("Load: expected codegen.scala to be a map")
	}

	if scala["version"] != "2.13" {
		t.Errorf("codegen.scala.version: want 2.13, got %v", scala["version"])
	}
}

func TestEnvSourceLoadNoMatchingVars(t *testing.T) {
	environ := func() []string {
		return []string{
			"OTHER_VAR=value",
			"ANOTHER_VAR=value2",
		}
	}

	src := newEnvSourceWithEnviron("MORPHIR", 6, environ)

	data, err := src.Load()
	if err != nil {
		t.Fatalf("Load: unexpected error: %v", err)
	}
	if data != nil {
		t.Errorf("Load: expected nil for no matching vars, got %v", data)
	}
}

func TestEnvSourceLoadEmptyEnvironment(t *testing.T) {
	environ := func() []string {
		return []string{}
	}

	src := newEnvSourceWithEnviron("MORPHIR", 6, environ)

	data, err := src.Load()
	if err != nil {
		t.Fatalf("Load: unexpected error: %v", err)
	}
	if data != nil {
		t.Errorf("Load: expected nil for empty environment, got %v", data)
	}
}

func TestParseEnvValueBool(t *testing.T) {
	tests := []struct {
		input string
		want  any
	}{
		{"true", true},
		{"false", false},
		{"True", true},
		{"FALSE", false},
		{"1", true},  // strconv.ParseBool accepts "1" as true
		{"0", false}, // strconv.ParseBool accepts "0" as false
	}

	for _, tt := range tests {
		got := parseEnvValue(tt.input)
		if got != tt.want {
			t.Errorf("parseEnvValue(%q): want %v (%T), got %v (%T)",
				tt.input, tt.want, tt.want, got, got)
		}
	}
}

func TestParseEnvValueInt(t *testing.T) {
	tests := []struct {
		input string
		want  int64
	}{
		// Note: "0" and "1" are parsed as bool by strconv.ParseBool
		{"42", 42},
		{"-100", -100},
		{"9223372036854775807", 9223372036854775807}, // max int64
		{"2", 2},
		{"100", 100},
	}

	for _, tt := range tests {
		got := parseEnvValue(tt.input)
		if got != tt.want {
			t.Errorf("parseEnvValue(%q): want %d, got %v (%T)",
				tt.input, tt.want, got, got)
		}
	}
}

func TestParseEnvValueDuration(t *testing.T) {
	tests := []struct {
		input string
		want  time.Duration
	}{
		{"5s", 5 * time.Second},
		{"1m30s", 90 * time.Second},
		{"2h", 2 * time.Hour},
		{"500ms", 500 * time.Millisecond},
	}

	for _, tt := range tests {
		got := parseEnvValue(tt.input)
		if got != tt.want {
			t.Errorf("parseEnvValue(%q): want %v, got %v (%T)",
				tt.input, tt.want, got, got)
		}
	}
}

func TestParseEnvValueString(t *testing.T) {
	tests := []string{
		"hello",
		"/path/to/file",
		"hello world",
		"",
		"not-a-number",
	}

	for _, input := range tests {
		got := parseEnvValue(input)
		if got != input {
			t.Errorf("parseEnvValue(%q): want %q, got %v (%T)",
				input, input, got, got)
		}
	}
}

func TestEnvKeyToPath(t *testing.T) {
	tests := []struct {
		input string
		want  []string
	}{
		{"IR_FORMAT_VERSION", []string{"ir_format_version"}},
		{"CODEGEN__GO__PACKAGE", []string{"codegen", "go", "package"}},
		{"CACHE_ENABLED", []string{"cache_enabled"}},
		{"A__B__C__D", []string{"a", "b", "c", "d"}},
	}

	for _, tt := range tests {
		got := envKeyToPath(tt.input)
		if !reflect.DeepEqual(got, tt.want) {
			t.Errorf("envKeyToPath(%q): want %v, got %v", tt.input, tt.want, got)
		}
	}
}

func TestEnvSourceImplementsInterface(t *testing.T) {
	var _ Source = (*EnvSource)(nil)
}

func TestEnvSourcePrefixCaseInsensitive(t *testing.T) {
	// Test that prefix is normalized to uppercase
	src := NewEnvSource("morphir", 6)

	if got := src.Path(); got != "MORPHIR_*" {
		t.Errorf("Path: want MORPHIR_*, got %q", got)
	}
}
