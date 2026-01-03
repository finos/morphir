package ir

// ModuleName is a unique identifier for a module within a package.
// It is represented by a Path, which is a list of names.
type ModuleName = Path

// QualifiedModuleName is a globally unique identifier for a module.
// It is represented by a tuple of the package path and the module path.
type QualifiedModuleName struct {
	packagePath Path
	modulePath  Path
}

// NewQualifiedModuleName creates a new qualified module name.
func NewQualifiedModuleName(packagePath Path, modulePath Path) QualifiedModuleName {
	return QualifiedModuleName{packagePath: packagePath, modulePath: modulePath}
}

func (q QualifiedModuleName) PackagePath() Path { return q.packagePath }
func (q QualifiedModuleName) ModulePath() Path  { return q.modulePath }

// Equal returns true if this qualified module name equals the other.
func (q QualifiedModuleName) Equal(other QualifiedModuleName) bool {
	return q.packagePath.Equal(other.packagePath) && q.modulePath.Equal(other.modulePath)
}

// ModuleSpecification represents a module specification.
// A module specification only contains types that are exposed publicly
// and type signatures for values that are exposed publicly.
//
// This matches Morphir.IR.Module.Specification in finos/morphir-elm.
type ModuleSpecification[TA any] struct {
	types  []ModuleSpecificationType[TA]
	values []ModuleSpecificationValue[TA]
	doc    *string
}

// ModuleSpecificationType represents a type in a module specification.
type ModuleSpecificationType[TA any] struct {
	name Name
	spec Documented[TypeSpecification[TA]]
}

// ModuleSpecificationTypeFromParts creates a module specification type.
func ModuleSpecificationTypeFromParts[TA any](name Name, spec Documented[TypeSpecification[TA]]) ModuleSpecificationType[TA] {
	return ModuleSpecificationType[TA]{name: name, spec: spec}
}

func (t ModuleSpecificationType[TA]) Name() Name                              { return t.name }
func (t ModuleSpecificationType[TA]) Spec() Documented[TypeSpecification[TA]] { return t.spec }

// ModuleSpecificationValue represents a value in a module specification.
type ModuleSpecificationValue[TA any] struct {
	name Name
	spec Documented[ValueSpecification[TA]]
}

// ModuleSpecificationValueFromParts creates a module specification value.
func ModuleSpecificationValueFromParts[TA any](name Name, spec Documented[ValueSpecification[TA]]) ModuleSpecificationValue[TA] {
	return ModuleSpecificationValue[TA]{name: name, spec: spec}
}

func (v ModuleSpecificationValue[TA]) Name() Name                               { return v.name }
func (v ModuleSpecificationValue[TA]) Spec() Documented[ValueSpecification[TA]] { return v.spec }

// NewModuleSpecification creates a new module specification.
func NewModuleSpecification[TA any](
	types []ModuleSpecificationType[TA],
	values []ModuleSpecificationValue[TA],
	doc *string,
) ModuleSpecification[TA] {
	var typesCopy []ModuleSpecificationType[TA]
	if len(types) > 0 {
		typesCopy = make([]ModuleSpecificationType[TA], len(types))
		copy(typesCopy, types)
	}
	var valuesCopy []ModuleSpecificationValue[TA]
	if len(values) > 0 {
		valuesCopy = make([]ModuleSpecificationValue[TA], len(values))
		copy(valuesCopy, values)
	}
	return ModuleSpecification[TA]{types: typesCopy, values: valuesCopy, doc: doc}
}

// Types returns the types in this module specification.
func (m ModuleSpecification[TA]) Types() []ModuleSpecificationType[TA] {
	if len(m.types) == 0 {
		return nil
	}
	copied := make([]ModuleSpecificationType[TA], len(m.types))
	copy(copied, m.types)
	return copied
}

// Values returns the values in this module specification.
func (m ModuleSpecification[TA]) Values() []ModuleSpecificationValue[TA] {
	if len(m.values) == 0 {
		return nil
	}
	copied := make([]ModuleSpecificationValue[TA], len(m.values))
	copy(copied, m.values)
	return copied
}

// Doc returns the module documentation.
func (m ModuleSpecification[TA]) Doc() *string { return m.doc }

// EmptyModuleSpecification returns an empty module specification.
func EmptyModuleSpecification[TA any]() ModuleSpecification[TA] {
	return ModuleSpecification[TA]{}
}

// ModuleDefinition represents a module definition.
// A module definition contains all the details including implementation
// and private types and values.
//
// This matches Morphir.IR.Module.Definition in finos/morphir-elm.
type ModuleDefinition[TA any, VA any] struct {
	types  []ModuleDefinitionType[TA]
	values []ModuleDefinitionValue[TA, VA]
	doc    *string
}

// ModuleDefinitionType represents a type in a module definition.
type ModuleDefinitionType[TA any] struct {
	name       Name
	definition AccessControlled[Documented[TypeDefinition[TA]]]
}

// ModuleDefinitionTypeFromParts creates a module definition type.
func ModuleDefinitionTypeFromParts[TA any](name Name, definition AccessControlled[Documented[TypeDefinition[TA]]]) ModuleDefinitionType[TA] {
	return ModuleDefinitionType[TA]{name: name, definition: definition}
}

func (t ModuleDefinitionType[TA]) Name() Name { return t.name }
func (t ModuleDefinitionType[TA]) Definition() AccessControlled[Documented[TypeDefinition[TA]]] {
	return t.definition
}

// ModuleDefinitionValue represents a value in a module definition.
type ModuleDefinitionValue[TA any, VA any] struct {
	name       Name
	definition AccessControlled[Documented[ValueDefinition[TA, VA]]]
}

// ModuleDefinitionValueFromParts creates a module definition value.
func ModuleDefinitionValueFromParts[TA any, VA any](name Name, definition AccessControlled[Documented[ValueDefinition[TA, VA]]]) ModuleDefinitionValue[TA, VA] {
	return ModuleDefinitionValue[TA, VA]{name: name, definition: definition}
}

func (v ModuleDefinitionValue[TA, VA]) Name() Name { return v.name }
func (v ModuleDefinitionValue[TA, VA]) Definition() AccessControlled[Documented[ValueDefinition[TA, VA]]] {
	return v.definition
}

// NewModuleDefinition creates a new module definition.
func NewModuleDefinition[TA any, VA any](
	types []ModuleDefinitionType[TA],
	values []ModuleDefinitionValue[TA, VA],
	doc *string,
) ModuleDefinition[TA, VA] {
	var typesCopy []ModuleDefinitionType[TA]
	if len(types) > 0 {
		typesCopy = make([]ModuleDefinitionType[TA], len(types))
		copy(typesCopy, types)
	}
	var valuesCopy []ModuleDefinitionValue[TA, VA]
	if len(values) > 0 {
		valuesCopy = make([]ModuleDefinitionValue[TA, VA], len(values))
		copy(valuesCopy, values)
	}
	return ModuleDefinition[TA, VA]{types: typesCopy, values: valuesCopy, doc: doc}
}

// Types returns the types in this module definition.
func (m ModuleDefinition[TA, VA]) Types() []ModuleDefinitionType[TA] {
	if len(m.types) == 0 {
		return nil
	}
	copied := make([]ModuleDefinitionType[TA], len(m.types))
	copy(copied, m.types)
	return copied
}

// Values returns the values in this module definition.
func (m ModuleDefinition[TA, VA]) Values() []ModuleDefinitionValue[TA, VA] {
	if len(m.values) == 0 {
		return nil
	}
	copied := make([]ModuleDefinitionValue[TA, VA], len(m.values))
	copy(copied, m.values)
	return copied
}

// Doc returns the module documentation.
func (m ModuleDefinition[TA, VA]) Doc() *string { return m.doc }

// EmptyModuleDefinition returns an empty module definition.
func EmptyModuleDefinition[TA any, VA any]() ModuleDefinition[TA, VA] {
	return ModuleDefinition[TA, VA]{}
}

// LookupTypeSpecification looks up a type specification by name in a module specification.
func LookupTypeSpecification[TA any](name Name, spec ModuleSpecification[TA]) *TypeSpecification[TA] {
	for _, t := range spec.types {
		if t.name.Equal(name) {
			val := t.spec.Value()
			return &val
		}
	}
	return nil
}

// LookupValueSpecification looks up a value specification by name in a module specification.
func LookupValueSpecification[TA any](name Name, spec ModuleSpecification[TA]) *ValueSpecification[TA] {
	for _, v := range spec.values {
		if v.name.Equal(name) {
			val := v.spec.Value()
			return &val
		}
	}
	return nil
}

// LookupValueDefinition looks up a value definition by name in a module definition.
func LookupValueDefinition[TA any, VA any](name Name, def ModuleDefinition[TA, VA]) *ValueDefinition[TA, VA] {
	for _, v := range def.values {
		if v.name.Equal(name) {
			val := v.definition.Value().Value()
			return &val
		}
	}
	return nil
}
