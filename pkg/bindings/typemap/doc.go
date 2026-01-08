// Package typemap provides a shared type mapping configuration system for all
// Morphir bindings (WIT, Protocol Buffers, JSON Schema, etc.).
//
// The package supports:
//   - Default type mappings defined in code via DefaultsProvider
//   - Configuration-based overrides via TOML files
//   - Bidirectional mappings (external type ↔ Morphir IR)
//   - O(1) lookup by type identifier
//   - Thread-safe global registry management
//
// # Basic Usage
//
// Create a registry with default mappings:
//
//	registry := typemap.NewBuilder("wit").
//		WithDefaults(witDefaults).
//		Build()
//
// Look up a type mapping:
//
//	if mapping, ok := registry.Lookup("u32"); ok {
//		// Use mapping.MorphirType
//	}
//
// # Configuration
//
// Type mappings can be overridden via TOML configuration:
//
//	[bindings.wit]
//	[[bindings.wit.primitives]]
//	external = "u128"
//	morphir = "Morphir.SDK:Int:Int128"
//	bidirectional = true
//	priority = 100
//
// Higher priority mappings override lower priority ones when building the registry.
package typemap
