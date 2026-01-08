package typemap

import (
	"sort"
)

// DefaultsProvider defines default mappings for a binding.
type DefaultsProvider interface {
	// DefaultPrimitives returns the default primitive type mappings.
	DefaultPrimitives() []TypeMapping
	// DefaultContainers returns the default container type mappings.
	DefaultContainers() []ContainerMapping
}

// Builder constructs Registry instances.
// Follows the builder pattern for fluent configuration.
type Builder struct {
	bindingName string
	primitives  []TypeMapping
	containers  []ContainerMapping
}

// NewBuilder creates a new Registry builder for the named binding.
func NewBuilder(bindingName string) *Builder {
	return &Builder{
		bindingName: bindingName,
		primitives:  make([]TypeMapping, 0),
		containers:  make([]ContainerMapping, 0),
	}
}

// AddPrimitive adds a primitive type mapping.
// The morphir parameter can be either a primitive kind ("Int") or FQName ("Morphir.SDK:Basics:Int").
func (b *Builder) AddPrimitive(external TypeID, morphir string, opts ...MappingOption) *Builder {
	ref, err := ParseMorphirTypeRef(morphir)
	if err != nil {
		// Skip invalid mappings
		return b
	}

	m := TypeMapping{
		ExternalType:  external,
		MorphirType:   ref,
		Bidirectional: true, // default
		Priority:      0,
	}

	for _, opt := range opts {
		opt(&m)
	}

	b.primitives = append(b.primitives, m)
	return b
}

// AddContainer adds a container type mapping.
func (b *Builder) AddContainer(externalPattern, morphirPattern string, paramCount int, opts ...ContainerOption) *Builder {
	c := ContainerMapping{
		ExternalPattern: externalPattern,
		MorphirPattern:  morphirPattern,
		TypeParamCount:  paramCount,
		Bidirectional:   true,
		Priority:        0,
	}

	for _, opt := range opts {
		opt(&c)
	}

	b.containers = append(b.containers, c)
	return b
}

// WithDefaults loads default mappings from a DefaultsProvider.
func (b *Builder) WithDefaults(provider DefaultsProvider) *Builder {
	if provider == nil {
		return b
	}
	for _, m := range provider.DefaultPrimitives() {
		b.primitives = append(b.primitives, m)
	}
	for _, c := range provider.DefaultContainers() {
		b.containers = append(b.containers, c)
	}
	return b
}

// WithConfig applies configuration overrides.
func (b *Builder) WithConfig(cfg TypeMappingConfig) *Builder {
	// Apply primitive overrides
	for _, override := range cfg.Primitives {
		ref, err := ParseMorphirTypeRef(override.MorphirType)
		if err != nil {
			continue
		}

		m := TypeMapping{
			ExternalType:  TypeID(override.ExternalType),
			MorphirType:   ref,
			Bidirectional: override.Bidirectional,
			Priority:      override.Priority,
		}

		b.primitives = append(b.primitives, m)
	}

	// Apply container overrides
	for _, override := range cfg.Containers {
		c := ContainerMapping{
			ExternalPattern: override.ExternalPattern,
			MorphirPattern:  override.MorphirPattern,
			TypeParamCount:  override.TypeParamCount,
			Bidirectional:   override.Bidirectional,
			Priority:        override.Priority,
		}

		b.containers = append(b.containers, c)
	}

	return b
}

// Build constructs the immutable Registry.
// Mappings are merged by priority; higher priority wins.
func (b *Builder) Build() *Registry {
	// Build primitive maps, resolving conflicts by priority
	primitives := make(map[TypeID]TypeMapping)
	primitivesReverse := make(map[string]TypeMapping)

	// Sort by priority (ascending) so higher priority comes last and overwrites
	sortedPrimitives := make([]TypeMapping, len(b.primitives))
	copy(sortedPrimitives, b.primitives)
	sort.Slice(sortedPrimitives, func(i, j int) bool {
		return sortedPrimitives[i].Priority < sortedPrimitives[j].Priority
	})

	for _, m := range sortedPrimitives {
		primitives[m.ExternalType] = m

		// Build reverse lookup
		key := m.MorphirType.String()
		if key != "" && m.Bidirectional {
			primitivesReverse[key] = m
		}
	}

	// Build container maps
	sortedContainers := make([]ContainerMapping, len(b.containers))
	copy(sortedContainers, b.containers)
	sort.Slice(sortedContainers, func(i, j int) bool {
		return sortedContainers[i].Priority < sortedContainers[j].Priority
	})

	// Deduplicate containers by pattern (higher priority wins)
	containerMap := make(map[string]ContainerMapping)
	for _, c := range sortedContainers {
		containerMap[c.ExternalPattern] = c
	}

	// Convert back to slice
	containers := make([]ContainerMapping, 0, len(containerMap))
	for _, c := range containerMap {
		containers = append(containers, c)
	}

	containersReverse := make(map[string]ContainerMapping)
	for _, c := range containers {
		if c.Bidirectional {
			containersReverse[c.MorphirPattern] = c
		}
	}

	return &Registry{
		bindingName:       b.bindingName,
		primitives:        primitives,
		primitivesReverse: primitivesReverse,
		containers:        containers,
		containersReverse: containersReverse,
	}
}

// MappingOption configures a TypeMapping.
type MappingOption func(*TypeMapping)

// WithPriority sets the priority for a mapping.
func WithPriority(p int) MappingOption {
	return func(m *TypeMapping) {
		m.Priority = p
	}
}

// OneWay marks a mapping as unidirectional.
func OneWay(dir Direction) MappingOption {
	return func(m *TypeMapping) {
		m.Bidirectional = false
		m.Direction = dir
	}
}

// WithMetadata adds metadata to a mapping.
func WithMetadata(key string, value any) MappingOption {
	return func(m *TypeMapping) {
		if m.Metadata == nil {
			m.Metadata = make(map[string]any)
		}
		m.Metadata[key] = value
	}
}

// ContainerOption configures a ContainerMapping.
type ContainerOption func(*ContainerMapping)

// WithContainerPriority sets the priority for a container mapping.
func WithContainerPriority(p int) ContainerOption {
	return func(c *ContainerMapping) {
		c.Priority = p
	}
}

// ContainerOneWay marks a container mapping as unidirectional.
func ContainerOneWay() ContainerOption {
	return func(c *ContainerMapping) {
		c.Bidirectional = false
	}
}
