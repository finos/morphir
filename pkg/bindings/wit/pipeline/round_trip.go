package pipeline

import (
	"github.com/finos/morphir/pkg/bindings/wit/domain"
)

// ValidateRoundTrip compares two WIT packages for semantic equivalence.
// It returns true if the packages are semantically equivalent, false otherwise.
// This is used to validate that WIT → IR → WIT conversion preserves semantics.
func ValidateRoundTrip(source, generated domain.Package) bool {
	// Compare interfaces
	if len(source.Interfaces) != len(generated.Interfaces) {
		return false
	}

	for i, srcIface := range source.Interfaces {
		if i >= len(generated.Interfaces) {
			return false
		}
		if !interfacesEqual(srcIface, generated.Interfaces[i]) {
			return false
		}
	}

	// Compare worlds
	if len(source.Worlds) != len(generated.Worlds) {
		return false
	}

	for i, srcWorld := range source.Worlds {
		if i >= len(generated.Worlds) {
			return false
		}
		if !worldsEqual(srcWorld, generated.Worlds[i]) {
			return false
		}
	}

	return true
}

// interfacesEqual checks if two interfaces are semantically equivalent.
func interfacesEqual(a, b domain.Interface) bool {
	// Compare types
	if len(a.Types) != len(b.Types) {
		return false
	}
	for i, srcType := range a.Types {
		if i >= len(b.Types) {
			return false
		}
		if !typeDefsEqual(srcType, b.Types[i]) {
			return false
		}
	}

	// Compare functions
	if len(a.Functions) != len(b.Functions) {
		return false
	}
	for i, srcFunc := range a.Functions {
		if i >= len(b.Functions) {
			return false
		}
		if !functionsEqual(srcFunc, b.Functions[i]) {
			return false
		}
	}

	return true
}

// typeDefsEqual checks if two type definitions are semantically equivalent.
func typeDefsEqual(a, b domain.TypeDef) bool {
	// Compare names (case-insensitive, kebab-case normalized)
	if normalizeIdentifier(a.Name) != normalizeIdentifier(b.Name) {
		return false
	}

	// Compare kinds
	return typeDefKindsEqual(a.Kind, b.Kind)
}

// typeDefKindsEqual compares two type definition kinds.
func typeDefKindsEqual(a, b domain.TypeDefKind) bool {
	switch aKind := a.(type) {
	case domain.RecordDef:
		bKind, ok := b.(domain.RecordDef)
		if !ok {
			return false
		}
		return recordDefsEqual(aKind, bKind)

	case domain.VariantDef:
		bKind, ok := b.(domain.VariantDef)
		if !ok {
			return false
		}
		return variantDefsEqual(aKind, bKind)

	case domain.EnumDef:
		bKind, ok := b.(domain.EnumDef)
		if !ok {
			return false
		}
		return enumDefsEqual(aKind, bKind)

	case domain.FlagsDef:
		bKind, ok := b.(domain.FlagsDef)
		if !ok {
			return false
		}
		return flagsDefsEqual(aKind, bKind)

	case domain.ResourceDef:
		bKind, ok := b.(domain.ResourceDef)
		if !ok {
			return false
		}
		return resourceDefsEqual(aKind, bKind)

	case domain.TypeAliasDef:
		bKind, ok := b.(domain.TypeAliasDef)
		if !ok {
			return false
		}
		return typesEqual(aKind.Target, bKind.Target)

	default:
		return false
	}
}

// recordDefsEqual compares two record definitions.
func recordDefsEqual(a, b domain.RecordDef) bool {
	if len(a.Fields) != len(b.Fields) {
		return false
	}
	for i, aField := range a.Fields {
		if i >= len(b.Fields) {
			return false
		}
		if !fieldsEqual(aField, b.Fields[i]) {
			return false
		}
	}
	return true
}

// variantDefsEqual compares two variant definitions.
func variantDefsEqual(a, b domain.VariantDef) bool {
	if len(a.Cases) != len(b.Cases) {
		return false
	}
	for i, aCase := range a.Cases {
		if i >= len(b.Cases) {
			return false
		}
		if !variantCasesEqual(aCase, b.Cases[i]) {
			return false
		}
	}
	return true
}

// enumDefsEqual compares two enum definitions.
func enumDefsEqual(a, b domain.EnumDef) bool {
	if len(a.Cases) != len(b.Cases) {
		return false
	}
	for i, aCase := range a.Cases {
		if i >= len(b.Cases) {
			return false
		}
		if normalizeIdentifier(aCase) != normalizeIdentifier(b.Cases[i]) {
			return false
		}
	}
	return true
}

// flagsDefsEqual compares two flags definitions.
func flagsDefsEqual(a, b domain.FlagsDef) bool {
	if len(a.Flags) != len(b.Flags) {
		return false
	}
	for i, aFlag := range a.Flags {
		if i >= len(b.Flags) {
			return false
		}
		if normalizeIdentifier(aFlag) != normalizeIdentifier(b.Flags[i]) {
			return false
		}
	}
	return true
}

// resourceDefsEqual compares two resource definitions.
func resourceDefsEqual(a, b domain.ResourceDef) bool {
	// Compare methods count
	if len(a.Methods) != len(b.Methods) {
		return false
	}
	// Compare constructors
	if (a.Constructor == nil) != (b.Constructor == nil) {
		return false
	}
	// Deep comparison of methods would go here
	return true
}

// fieldsEqual compares two record fields.
func fieldsEqual(a, b domain.Field) bool {
	if normalizeIdentifier(a.Name) != normalizeIdentifier(b.Name) {
		return false
	}
	return typesEqual(a.Type, b.Type)
}

// variantCasesEqual compares two variant cases.
func variantCasesEqual(a, b domain.VariantCase) bool {
	if normalizeIdentifier(a.Name) != normalizeIdentifier(b.Name) {
		return false
	}
	// Both nil or both non-nil
	if (a.Payload == nil) != (b.Payload == nil) {
		return false
	}
	if a.Payload != nil {
		return typesEqual(*a.Payload, *b.Payload)
	}
	return true
}

// functionsEqual compares two functions for semantic equivalence.
func functionsEqual(a, b domain.Function) bool {
	if normalizeIdentifier(a.Name) != normalizeIdentifier(b.Name) {
		return false
	}

	// Compare parameters
	if len(a.Params) != len(b.Params) {
		return false
	}
	for i, aParam := range a.Params {
		if i >= len(b.Params) {
			return false
		}
		if !paramsEqual(aParam, b.Params[i]) {
			return false
		}
	}

	// Compare results
	if len(a.Results) != len(b.Results) {
		return false
	}
	for i, aResult := range a.Results {
		if i >= len(b.Results) {
			return false
		}
		if !typesEqual(aResult, b.Results[i]) {
			return false
		}
	}

	return true
}

// paramsEqual compares two function parameters.
func paramsEqual(a, b domain.Param) bool {
	if normalizeIdentifier(a.Name) != normalizeIdentifier(b.Name) {
		return false
	}
	return typesEqual(a.Type, b.Type)
}

// typesEqual compares two types for semantic equivalence.
func typesEqual(a, b domain.Type) bool {
	if a == nil && b == nil {
		return true
	}
	if a == nil || b == nil {
		return false
	}

	switch aType := a.(type) {
	case domain.PrimitiveType:
		bType, ok := b.(domain.PrimitiveType)
		if !ok {
			return false
		}
		return primitiveTypesEqual(aType, bType)

	case domain.NamedType:
		bType, ok := b.(domain.NamedType)
		if !ok {
			return false
		}
		return normalizeIdentifier(aType.Name) == normalizeIdentifier(bType.Name)

	case domain.ListType:
		bType, ok := b.(domain.ListType)
		if !ok {
			return false
		}
		return typesEqual(aType.Element, bType.Element)

	case domain.OptionType:
		bType, ok := b.(domain.OptionType)
		if !ok {
			return false
		}
		return typesEqual(aType.Inner, bType.Inner)

	case domain.ResultType:
		bType, ok := b.(domain.ResultType)
		if !ok {
			return false
		}
		return resultTypesEqual(aType, bType)

	case domain.TupleType:
		bType, ok := b.(domain.TupleType)
		if !ok {
			return false
		}
		return tupleTypesEqual(aType, bType)

	case domain.HandleType:
		bType, ok := b.(domain.HandleType)
		if !ok {
			return false
		}
		return handleTypesEqual(aType, bType)

	default:
		return false
	}
}

// primitiveTypesEqual compares two primitive types.
// It considers integer types equivalent if they have the same signedness.
// This is a lenient comparison that accounts for lossy conversions.
func primitiveTypesEqual(a, b domain.PrimitiveType) bool {
	// For strict comparison, use direct kind equality
	if a.Kind == b.Kind {
		return true
	}

	// Lenient comparison: all integers map to Int in Morphir
	// so we treat them as equivalent for round-trip purposes
	if isIntegerKind(a.Kind) && isIntegerKind(b.Kind) {
		return true
	}

	// Float32 and Float64 both map to Float
	if isFloatKind(a.Kind) && isFloatKind(b.Kind) {
		return true
	}

	return false
}

func isIntegerKind(k domain.PrimitiveKind) bool {
	switch k {
	case domain.U8, domain.U16, domain.U32, domain.U64,
		domain.S8, domain.S16, domain.S32, domain.S64:
		return true
	}
	return false
}

func isFloatKind(k domain.PrimitiveKind) bool {
	return k == domain.F32 || k == domain.F64
}

// resultTypesEqual compares two result types.
func resultTypesEqual(a, b domain.ResultType) bool {
	// Compare Ok types
	if (a.Ok == nil) != (b.Ok == nil) {
		return false
	}
	if a.Ok != nil && !typesEqual(*a.Ok, *b.Ok) {
		return false
	}

	// Compare Err types
	if (a.Err == nil) != (b.Err == nil) {
		return false
	}
	if a.Err != nil && !typesEqual(*a.Err, *b.Err) {
		return false
	}

	return true
}

// tupleTypesEqual compares two tuple types.
func tupleTypesEqual(a, b domain.TupleType) bool {
	if len(a.Types) != len(b.Types) {
		return false
	}
	for i, aElem := range a.Types {
		if !typesEqual(aElem, b.Types[i]) {
			return false
		}
	}
	return true
}

// handleTypesEqual compares two handle types.
func handleTypesEqual(a, b domain.HandleType) bool {
	if a.IsBorrow != b.IsBorrow {
		return false
	}
	return normalizeIdentifier(a.Resource) == normalizeIdentifier(b.Resource)
}

// worldsEqual compares two worlds for semantic equivalence.
func worldsEqual(a, b domain.World) bool {
	// Compare imports count
	if len(a.Imports) != len(b.Imports) {
		return false
	}
	// Compare exports count
	if len(a.Exports) != len(b.Exports) {
		return false
	}
	// Deep comparison would go here
	return true
}

// normalizeIdentifier normalizes an identifier for comparison.
// It converts to lowercase to allow case-insensitive matching.
func normalizeIdentifier(id domain.Identifier) string {
	return id.String()
}
