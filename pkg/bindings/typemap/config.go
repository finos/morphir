package typemap

// TypeMappingConfig represents the TOML configuration for type mappings.
type TypeMappingConfig struct {
	// Primitives holds primitive type mapping overrides.
	Primitives []PrimitiveMappingConfig `toml:"primitives"`

	// Containers holds container type mapping overrides.
	Containers []ContainerMappingConfig `toml:"containers"`
}

// PrimitiveMappingConfig is the TOML representation of a primitive mapping.
type PrimitiveMappingConfig struct {
	// ExternalType is the external type identifier (e.g., "u32", "int32").
	ExternalType string `toml:"external"`

	// MorphirType is the Morphir type reference (e.g., "Int", "Morphir.SDK:Basics:Int").
	MorphirType string `toml:"morphir"`

	// Bidirectional indicates whether this mapping works both directions.
	Bidirectional bool `toml:"bidirectional"`

	// Priority determines precedence (higher wins).
	Priority int `toml:"priority"`
}

// ContainerMappingConfig is the TOML representation of a container mapping.
type ContainerMappingConfig struct {
	// ExternalPattern is the container pattern (e.g., "list", "option").
	ExternalPattern string `toml:"external_pattern"`

	// MorphirPattern is the Morphir container pattern (e.g., "Morphir.SDK:List:List").
	MorphirPattern string `toml:"morphir_pattern"`

	// TypeParamCount is the number of type parameters.
	TypeParamCount int `toml:"type_params"`

	// Bidirectional indicates whether this mapping works both directions.
	Bidirectional bool `toml:"bidirectional"`

	// Priority determines precedence (higher wins).
	Priority int `toml:"priority"`
}

// IsEmpty returns true if the config has no mappings.
func (c TypeMappingConfig) IsEmpty() bool {
	return len(c.Primitives) == 0 && len(c.Containers) == 0
}
