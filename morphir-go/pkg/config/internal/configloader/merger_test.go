package configloader

import (
	"reflect"
	"testing"
)

func TestDeepMergeFlatMaps(t *testing.T) {
	base := map[string]any{
		"key1": "value1",
		"key2": "value2",
	}
	overlay := map[string]any{
		"key2": "override",
		"key3": "value3",
	}

	result := DeepMerge(base, overlay)

	if result["key1"] != "value1" {
		t.Errorf("key1: want value1, got %v", result["key1"])
	}
	if result["key2"] != "override" {
		t.Errorf("key2: want override, got %v", result["key2"])
	}
	if result["key3"] != "value3" {
		t.Errorf("key3: want value3, got %v", result["key3"])
	}
}

func TestDeepMergeNestedMaps(t *testing.T) {
	base := map[string]any{
		"section": map[string]any{
			"key1": "value1",
			"key2": "value2",
		},
	}
	overlay := map[string]any{
		"section": map[string]any{
			"key2": "override",
			"key3": "value3",
		},
	}

	result := DeepMerge(base, overlay)

	section, ok := result["section"].(map[string]any)
	if !ok {
		t.Fatal("section should be a map")
	}

	if section["key1"] != "value1" {
		t.Errorf("section.key1: want value1, got %v", section["key1"])
	}
	if section["key2"] != "override" {
		t.Errorf("section.key2: want override, got %v", section["key2"])
	}
	if section["key3"] != "value3" {
		t.Errorf("section.key3: want value3, got %v", section["key3"])
	}
}

func TestDeepMergeDeeplyNestedMaps(t *testing.T) {
	base := map[string]any{
		"level1": map[string]any{
			"level2": map[string]any{
				"level3": map[string]any{
					"key": "base",
				},
			},
		},
	}
	overlay := map[string]any{
		"level1": map[string]any{
			"level2": map[string]any{
				"level3": map[string]any{
					"key": "override",
				},
			},
		},
	}

	result := DeepMerge(base, overlay)

	level1 := result["level1"].(map[string]any)
	level2 := level1["level2"].(map[string]any)
	level3 := level2["level3"].(map[string]any)

	if level3["key"] != "override" {
		t.Errorf("level1.level2.level3.key: want override, got %v", level3["key"])
	}
}

func TestDeepMergeSliceReplacement(t *testing.T) {
	base := map[string]any{
		"targets": []string{"go", "scala"},
	}
	overlay := map[string]any{
		"targets": []string{"typescript"},
	}

	result := DeepMerge(base, overlay)

	targets, ok := result["targets"].([]string)
	if !ok {
		t.Fatal("targets should be a []string")
	}

	if len(targets) != 1 || targets[0] != "typescript" {
		t.Errorf("targets: want [typescript], got %v", targets)
	}
}

func TestDeepMergeNilOverlayValuesIgnored(t *testing.T) {
	base := map[string]any{
		"key1": "value1",
		"key2": "value2",
	}
	overlay := map[string]any{
		"key1": nil, // Should not override
		"key2": "override",
	}

	result := DeepMerge(base, overlay)

	if result["key1"] != "value1" {
		t.Errorf("key1: nil overlay should not override, got %v", result["key1"])
	}
	if result["key2"] != "override" {
		t.Errorf("key2: want override, got %v", result["key2"])
	}
}

func TestDeepMergePreservesBaseWhenOverlayMissing(t *testing.T) {
	base := map[string]any{
		"existing": "value",
		"nested": map[string]any{
			"deep": "value",
		},
	}
	overlay := map[string]any{
		"new": "added",
	}

	result := DeepMerge(base, overlay)

	if result["existing"] != "value" {
		t.Errorf("existing: want value, got %v", result["existing"])
	}
	if result["new"] != "added" {
		t.Errorf("new: want added, got %v", result["new"])
	}

	nested := result["nested"].(map[string]any)
	if nested["deep"] != "value" {
		t.Errorf("nested.deep: want value, got %v", nested["deep"])
	}
}

func TestDeepMergeNilInputs(t *testing.T) {
	// Both nil
	result := DeepMerge(nil, nil)
	if result != nil {
		t.Errorf("DeepMerge(nil, nil): want nil, got %v", result)
	}

	// Base nil
	overlay := map[string]any{"key": "value"}
	result = DeepMerge(nil, overlay)
	if result["key"] != "value" {
		t.Errorf("DeepMerge(nil, overlay): want key=value, got %v", result)
	}

	// Overlay nil
	base := map[string]any{"key": "value"}
	result = DeepMerge(base, nil)
	if result["key"] != "value" {
		t.Errorf("DeepMerge(base, nil): want key=value, got %v", result)
	}
}

func TestDeepMergeDoesNotModifyInputs(t *testing.T) {
	base := map[string]any{
		"key": "original",
		"nested": map[string]any{
			"inner": "original",
		},
	}
	overlay := map[string]any{
		"key": "modified",
	}

	_ = DeepMerge(base, overlay)

	// Check base is unchanged
	if base["key"] != "original" {
		t.Errorf("base was modified: key = %v", base["key"])
	}
	nested := base["nested"].(map[string]any)
	if nested["inner"] != "original" {
		t.Errorf("base.nested was modified: inner = %v", nested["inner"])
	}
}

func TestDeepMergeMapReplacesNonMap(t *testing.T) {
	base := map[string]any{
		"key": "string value",
	}
	overlay := map[string]any{
		"key": map[string]any{
			"nested": "value",
		},
	}

	result := DeepMerge(base, overlay)

	keyMap, ok := result["key"].(map[string]any)
	if !ok {
		t.Fatalf("key should be map after merge, got %T", result["key"])
	}
	if keyMap["nested"] != "value" {
		t.Errorf("key.nested: want value, got %v", keyMap["nested"])
	}
}

func TestDeepMergeNonMapReplacesMap(t *testing.T) {
	base := map[string]any{
		"key": map[string]any{
			"nested": "value",
		},
	}
	overlay := map[string]any{
		"key": "string value",
	}

	result := DeepMerge(base, overlay)

	if result["key"] != "string value" {
		t.Errorf("key: want 'string value', got %v", result["key"])
	}
}

func TestMergeAll(t *testing.T) {
	config1 := map[string]any{"a": "1", "b": "1"}
	config2 := map[string]any{"b": "2", "c": "2"}
	config3 := map[string]any{"c": "3", "d": "3"}

	result := MergeAll(config1, config2, config3)

	expected := map[string]any{
		"a": "1", // from config1
		"b": "2", // overridden by config2
		"c": "3", // overridden by config3
		"d": "3", // from config3
	}

	if !reflect.DeepEqual(result, expected) {
		t.Errorf("MergeAll: want %v, got %v", expected, result)
	}
}

func TestMergeAllEmpty(t *testing.T) {
	result := MergeAll()
	if result != nil {
		t.Errorf("MergeAll(): want nil, got %v", result)
	}
}

func TestMergeAllWithNils(t *testing.T) {
	config1 := map[string]any{"a": "1"}
	config2 := map[string]any{"b": "2"}

	result := MergeAll(config1, nil, config2)

	if result["a"] != "1" {
		t.Errorf("a: want 1, got %v", result["a"])
	}
	if result["b"] != "2" {
		t.Errorf("b: want 2, got %v", result["b"])
	}
}

func TestDeepCopyValueSlices(t *testing.T) {
	original := []string{"a", "b", "c"}
	copied := deepCopyValue(original).([]string)

	// Modify original
	original[0] = "modified"

	// Copy should be unaffected
	if copied[0] != "a" {
		t.Errorf("deep copy failed: copied slice was modified")
	}
}

func TestDeepCopyValueNestedMaps(t *testing.T) {
	original := map[string]any{
		"level1": map[string]any{
			"level2": "value",
		},
	}
	copied := deepCopyValue(original).(map[string]any)

	// Modify original
	original["level1"].(map[string]any)["level2"] = "modified"

	// Copy should be unaffected
	level1 := copied["level1"].(map[string]any)
	if level1["level2"] != "value" {
		t.Errorf("deep copy failed: copied map was modified")
	}
}
