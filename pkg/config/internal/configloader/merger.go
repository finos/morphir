// Package configloader provides internal configuration loading and merging logic.
//
// This package is internal and should not be imported by external code.
// Use the public config package API instead.
package configloader

// DeepMerge recursively merges the overlay map into the base map.
// The merge follows these rules:
//   - Values from overlay take precedence over base
//   - Nested maps are merged recursively (not replaced wholesale)
//   - Slices are replaced entirely (not appended)
//   - Nil values in overlay are ignored (do not override base)
//
// Returns a new map without modifying the inputs.
func DeepMerge(base, overlay map[string]any) map[string]any {
	if base == nil && overlay == nil {
		return nil
	}

	result := make(map[string]any)

	// Copy all base values first
	for k, v := range base {
		result[k] = deepCopyValue(v)
	}

	// Merge overlay values
	for k, overlayVal := range overlay {
		if overlayVal == nil {
			// Nil values in overlay don't override base
			continue
		}

		baseVal, exists := result[k]
		if !exists {
			// Key doesn't exist in base, just copy overlay value
			result[k] = deepCopyValue(overlayVal)
			continue
		}

		// Both exist, check if both are maps for recursive merge
		baseMap, baseIsMap := baseVal.(map[string]any)
		overlayMap, overlayIsMap := overlayVal.(map[string]any)

		if baseIsMap && overlayIsMap {
			// Recursively merge nested maps
			result[k] = DeepMerge(baseMap, overlayMap)
		} else {
			// Replace with overlay value (includes slices, primitives, etc.)
			result[k] = deepCopyValue(overlayVal)
		}
	}

	return result
}

// MergeAll merges multiple configuration maps in order.
// Later maps take precedence over earlier maps.
// This is equivalent to chaining DeepMerge calls.
func MergeAll(configs ...map[string]any) map[string]any {
	if len(configs) == 0 {
		return nil
	}

	result := deepCopyValue(configs[0]).(map[string]any)
	for i := 1; i < len(configs); i++ {
		if configs[i] != nil {
			result = DeepMerge(result, configs[i])
		}
	}

	return result
}

// deepCopyValue creates a deep copy of a value.
// This ensures the merged result is independent of the inputs.
func deepCopyValue(v any) any {
	if v == nil {
		return nil
	}

	switch val := v.(type) {
	case map[string]any:
		result := make(map[string]any, len(val))
		for k, v := range val {
			result[k] = deepCopyValue(v)
		}
		return result

	case []any:
		result := make([]any, len(val))
		for i, v := range val {
			result[i] = deepCopyValue(v)
		}
		return result

	case []string:
		result := make([]string, len(val))
		copy(result, val)
		return result

	case []int:
		result := make([]int, len(val))
		copy(result, val)
		return result

	case []int64:
		result := make([]int64, len(val))
		copy(result, val)
		return result

	case []float64:
		result := make([]float64, len(val))
		copy(result, val)
		return result

	default:
		// Primitives (string, int, bool, etc.) are copied by value
		return val
	}
}
