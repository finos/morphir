package typemap

// Registry holds type mappings for a specific binding.
// It is immutable after construction; use Builder to create instances.
type Registry struct {
	// bindingName identifies the binding (e.g., "wit", "protobuf", "jsonschema").
	bindingName string

	// primitives maps external type IDs to their Morphir equivalents.
	// Used for O(1) lookup by external type.
	primitives map[TypeID]TypeMapping

	// primitivesReverse maps Morphir type strings to external types.
	// Used for O(1) reverse lookup (FromMorphir direction).
	primitivesReverse map[string]TypeMapping

	// containers holds container/parameterized type mappings.
	containers []ContainerMapping

	// containersReverse maps Morphir container pattern strings to container mappings.
	containersReverse map[string]ContainerMapping
}

// BindingName returns the name of the binding this registry serves.
func (r *Registry) BindingName() string {
	return r.bindingName
}

// Lookup finds a mapping for an external type ID.
// Returns the mapping and true if found, zero value and false otherwise.
func (r *Registry) Lookup(id TypeID) (TypeMapping, bool) {
	if r == nil || r.primitives == nil {
		return TypeMapping{}, false
	}
	m, ok := r.primitives[id]
	return m, ok
}

// LookupReverse finds a mapping for a Morphir type.
// Used when emitting from Morphir IR to external format.
func (r *Registry) LookupReverse(ref MorphirTypeRef) (TypeMapping, bool) {
	if r == nil || r.primitivesReverse == nil {
		return TypeMapping{}, false
	}
	m, ok := r.primitivesReverse[ref.String()]
	return m, ok
}

// LookupContainer finds a container mapping by external pattern.
func (r *Registry) LookupContainer(pattern string) (ContainerMapping, bool) {
	if r == nil {
		return ContainerMapping{}, false
	}
	for _, c := range r.containers {
		if c.ExternalPattern == pattern {
			return c, true
		}
	}
	return ContainerMapping{}, false
}

// LookupContainerReverse finds a container mapping by Morphir pattern.
func (r *Registry) LookupContainerReverse(morphirPattern string) (ContainerMapping, bool) {
	if r == nil || r.containersReverse == nil {
		return ContainerMapping{}, false
	}
	c, ok := r.containersReverse[morphirPattern]
	return c, ok
}

// AllPrimitives returns all primitive type mappings.
// Returns a defensive copy.
func (r *Registry) AllPrimitives() []TypeMapping {
	if r == nil || r.primitives == nil {
		return nil
	}
	result := make([]TypeMapping, 0, len(r.primitives))
	for _, m := range r.primitives {
		result = append(result, m)
	}
	return result
}

// AllContainers returns all container type mappings.
// Returns a defensive copy.
func (r *Registry) AllContainers() []ContainerMapping {
	if r == nil || r.containers == nil {
		return nil
	}
	result := make([]ContainerMapping, len(r.containers))
	copy(result, r.containers)
	return result
}

// PrimitiveCount returns the number of primitive type mappings.
func (r *Registry) PrimitiveCount() int {
	if r == nil || r.primitives == nil {
		return 0
	}
	return len(r.primitives)
}

// ContainerCount returns the number of container type mappings.
func (r *Registry) ContainerCount() int {
	if r == nil || r.containers == nil {
		return 0
	}
	return len(r.containers)
}
