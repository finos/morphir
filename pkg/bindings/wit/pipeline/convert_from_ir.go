package pipeline

import (
	"fmt"
	"strings"

	"github.com/finos/morphir/pkg/bindings/typemap"
	"github.com/finos/morphir/pkg/bindings/wit"
	"github.com/finos/morphir/pkg/bindings/wit/domain"
	"github.com/finos/morphir/pkg/models/ir"
	"github.com/finos/morphir/pkg/pipeline"
)

// ConvertFromIR converts a Morphir IR ModuleDefinition to a WIT domain.Package.
// It returns the converted package and any diagnostics generated during conversion.
func ConvertFromIR(module ir.ModuleDefinition[any, any], opts GenOptions) (domain.Package, []pipeline.Diagnostic) {
	c := &fromIRConverter{
		registry: wit.DefaultWITRegistry(),
		opts:     opts,
		stepName: "wit-gen",
	}
	return c.convert(module)
}

// fromIRConverter handles the conversion from Morphir IR to WIT.
type fromIRConverter struct {
	registry    *typemap.Registry
	opts        GenOptions
	stepName    string
	diagnostics []pipeline.Diagnostic
}

func (c *fromIRConverter) addDiagnostic(d pipeline.Diagnostic) {
	c.diagnostics = append(c.diagnostics, d)
}

func (c *fromIRConverter) convert(module ir.ModuleDefinition[any, any]) (domain.Package, []pipeline.Diagnostic) {
	var types []domain.TypeDef
	var functions []domain.Function

	// Convert types
	for _, modType := range module.Types() {
		if td := c.convertTypeDef(modType); td != nil {
			types = append(types, *td)
		}
	}

	// Convert values (functions)
	for _, modValue := range module.Values() {
		if fn := c.convertFunction(modValue); fn != nil {
			functions = append(functions, *fn)
		}
	}

	// Create a default interface to hold all types and functions
	iface := domain.Interface{
		Name:      domain.MustIdentifier("generated"),
		Types:     types,
		Functions: functions,
	}

	// Get documentation
	var docs domain.Documentation
	if module.Doc() != nil {
		docs = domain.NewDocumentation(*module.Doc())
	}

	pkg := domain.Package{
		Namespace:  domain.MustNamespace("generated"),
		Name:       domain.MustPackageName("module"),
		Interfaces: []domain.Interface{iface},
		Docs:       docs,
	}

	return pkg, c.diagnostics
}

func (c *fromIRConverter) convertTypeDef(modType ir.ModuleDefinitionType[any]) *domain.TypeDef {
	name := nameToString(modType.Name())

	// Get the type definition
	acl := modType.Definition()
	documented := acl.Value()
	typeDef := documented.Value()

	var kind domain.TypeDefKind

	switch td := typeDef.(type) {
	case ir.TypeAliasDefinition[any]:
		// Check if it's a record type
		aliasType := td.Expression()
		if recType, ok := aliasType.(ir.TypeRecord[any]); ok {
			kind = c.convertRecord(recType)
		} else {
			// Type alias to something else
			targetType := c.convertType(aliasType)
			kind = domain.TypeAliasDef{Target: targetType}
		}

	case ir.CustomTypeDefinition[any]:
		// Check if it's an enum or variant
		constructors := td.Constructors()
		ctors := constructors.Value()
		if len(ctors) > 0 {
			if isEnum(ctors) {
				kind = c.convertEnum(ctors)
			} else {
				kind = c.convertVariant(ctors)
			}
		}

	default:
		c.addDiagnostic(ConversionError(
			fmt.Sprintf("unknown type definition kind: %T", typeDef),
			c.stepName,
		))
		return nil
	}

	// Get documentation
	var docs domain.Documentation
	if documented.Doc() != "" {
		docs = domain.NewDocumentation(documented.Doc())
	}

	id, err := domain.NewIdentifier(toKebabCase(name))
	if err != nil {
		c.addDiagnostic(ConversionError(
			fmt.Sprintf("invalid identifier: %s", name),
			c.stepName,
		))
		return nil
	}

	return &domain.TypeDef{
		Name: id,
		Kind: kind,
		Docs: docs,
	}
}

func (c *fromIRConverter) convertRecord(recType ir.TypeRecord[any]) domain.RecordDef {
	var fields []domain.Field
	for _, f := range recType.Fields() {
		fieldType := c.convertType(f.Type())
		fieldName, err := domain.NewIdentifier(toKebabCase(f.Name().ToCamelCase()))
		if err != nil {
			c.addDiagnostic(ConversionError(
				fmt.Sprintf("invalid field name: %s", f.Name().ToCamelCase()),
				c.stepName,
			))
			continue
		}
		fields = append(fields, domain.Field{
			Name: fieldName,
			Type: fieldType,
		})
	}
	return domain.RecordDef{Fields: fields}
}

func (c *fromIRConverter) convertEnum(ctors ir.TypeConstructors[any]) domain.EnumDef {
	var cases []domain.Identifier
	for _, ctor := range ctors {
		caseName, err := domain.NewIdentifier(toKebabCase(ctor.Name().ToCamelCase()))
		if err != nil {
			c.addDiagnostic(ConversionError(
				fmt.Sprintf("invalid enum case name: %s", ctor.Name().ToCamelCase()),
				c.stepName,
			))
			continue
		}
		cases = append(cases, caseName)
	}
	return domain.EnumDef{Cases: cases}
}

func (c *fromIRConverter) convertVariant(ctors ir.TypeConstructors[any]) domain.VariantDef {
	var cases []domain.VariantCase
	for _, ctor := range ctors {
		caseName, err := domain.NewIdentifier(toKebabCase(ctor.Name().ToCamelCase()))
		if err != nil {
			c.addDiagnostic(ConversionError(
				fmt.Sprintf("invalid variant case name: %s", ctor.Name().ToCamelCase()),
				c.stepName,
			))
			continue
		}

		var payload *domain.Type
		args := ctor.Args()
		if len(args) > 0 {
			// Take the first argument's type as the payload
			argType := c.convertType(args[0].Type())
			payload = &argType
		}

		cases = append(cases, domain.VariantCase{
			Name:    caseName,
			Payload: payload,
		})
	}
	return domain.VariantDef{Cases: cases}
}

func (c *fromIRConverter) convertFunction(modValue ir.ModuleDefinitionValue[any, any]) *domain.Function {
	name := nameToString(modValue.Name())

	// Get the value definition
	acl := modValue.Definition()
	documented := acl.Value()
	valueDef := documented.Value()

	// Extract parameters
	var params []domain.Param
	for _, input := range valueDef.InputTypes() {
		paramName, err := domain.NewIdentifier(toKebabCase(input.Name().ToCamelCase()))
		if err != nil {
			c.addDiagnostic(ConversionError(
				fmt.Sprintf("invalid parameter name: %s", input.Name().ToCamelCase()),
				c.stepName,
			))
			continue
		}
		paramType := c.convertType(input.Type())
		params = append(params, domain.Param{
			Name: paramName,
			Type: paramType,
		})
	}

	// Extract result type
	var results []domain.Type
	outputType := valueDef.OutputType()
	if outputType != nil {
		if !isUnit(outputType) {
			// Check if it's a tuple (multiple results)
			if tuple, ok := outputType.(ir.TypeTuple[any]); ok {
				for _, elem := range tuple.Elements() {
					results = append(results, c.convertType(elem))
				}
			} else {
				results = append(results, c.convertType(outputType))
			}
		}
	}

	// Get documentation
	var docs domain.Documentation
	if documented.Doc() != "" {
		docs = domain.NewDocumentation(documented.Doc())
	}

	id, err := domain.NewIdentifier(toKebabCase(name))
	if err != nil {
		c.addDiagnostic(ConversionError(
			fmt.Sprintf("invalid function name: %s", name),
			c.stepName,
		))
		return nil
	}

	return &domain.Function{
		Name:    id,
		Params:  params,
		Results: results,
		Docs:    docs,
	}
}

func (c *fromIRConverter) convertType(t ir.Type[any]) domain.Type {
	if t == nil {
		return nil
	}

	switch ty := t.(type) {
	case ir.TypeReference[any]:
		return c.convertTypeReference(ty)

	case ir.TypeVariable[any]:
		// Named type reference
		return domain.NamedType{Name: domain.MustIdentifier(toKebabCase(ty.Name().ToCamelCase()))}

	case ir.TypeRecord[any]:
		// Inline record - not directly representable in WIT
		c.addDiagnostic(DiagnosticWarn(
			CodeConversionError,
			"inline record converted to named type",
			c.stepName,
		))
		return nil

	case ir.TypeTuple[any]:
		var elements []domain.Type
		for _, elem := range ty.Elements() {
			elements = append(elements, c.convertType(elem))
		}
		return domain.TupleType{Types: elements}

	case ir.TypeUnit[any]:
		// Unit type - no equivalent in WIT
		return nil

	default:
		c.addDiagnostic(UnknownType(fmt.Sprintf("%T", t), c.stepName))
		return nil
	}
}

func (c *fromIRConverter) convertTypeReference(ref ir.TypeReference[any]) domain.Type {
	fqn := ref.FullyQualifiedName()
	localName := nameToString(fqn.LocalName())
	modulePath := fqn.ModulePath()
	packagePath := fqn.PackagePath()

	// Check if this is a Morphir SDK type
	if isSDKType(packagePath) {
		return c.convertSDKType(localName, modulePath, ref.TypeParams())
	}

	// Try reverse lookup in registry
	morphirRef := typemap.MorphirTypeRef{PrimitiveKind: localName}
	if mapping, ok := c.registry.LookupReverse(morphirRef); ok {
		return c.externalTypeToWIT(mapping.ExternalType)
	}

	// User-defined type reference
	return domain.NamedType{Name: domain.MustIdentifier(toKebabCase(localName))}
}

func (c *fromIRConverter) convertSDKType(localName string, modulePath ir.Path, typeParams []ir.Type[any]) domain.Type {
	// Determine the module name
	var moduleName string
	parts := modulePath.Parts()
	if len(parts) > 0 {
		moduleName = nameToString(parts[len(parts)-1])
	}

	// Handle different SDK types
	switch moduleName {
	case "Basics":
		return c.convertBasicsType(localName)
	case "List":
		if localName == "List" && len(typeParams) > 0 {
			elemType := c.convertType(typeParams[0])
			return domain.ListType{Element: elemType}
		}
	case "Maybe":
		if localName == "Maybe" && len(typeParams) > 0 {
			innerType := c.convertType(typeParams[0])
			return domain.OptionType{Inner: innerType}
		}
	case "Result":
		if localName == "Result" && len(typeParams) >= 2 {
			// Morphir Result has error first: Result E T
			errType := c.convertType(typeParams[0])
			okType := c.convertType(typeParams[1])
			return domain.ResultType{Ok: &okType, Err: &errType}
		}
	}

	// Fall back to treating it as a named type
	c.addDiagnostic(DiagnosticWarn(
		CodeConversionError,
		fmt.Sprintf("unknown SDK type: %s.%s", moduleName, localName),
		c.stepName,
	))
	return domain.NamedType{Name: domain.MustIdentifier(toKebabCase(localName))}
}

func (c *fromIRConverter) convertBasicsType(localName string) domain.Type {
	// Try reverse lookup for basic types
	morphirRef := typemap.MorphirTypeRef{PrimitiveKind: localName}
	if mapping, ok := c.registry.LookupReverse(morphirRef); ok {
		return c.externalTypeToWIT(mapping.ExternalType)
	}

	// Common basics mappings
	switch localName {
	case "Bool":
		return domain.PrimitiveType{Kind: domain.Bool}
	case "Int":
		// Default to s32 for Int
		c.addDiagnostic(DiagnosticInfo(
			CodeIntPrecisionLost,
			"Int converted to s32 (size unknown)",
			c.stepName,
		))
		return domain.PrimitiveType{Kind: domain.S32}
	case "Float":
		// Default to f64 for Float
		return domain.PrimitiveType{Kind: domain.F64}
	case "String":
		return domain.PrimitiveType{Kind: domain.String}
	case "Char":
		return domain.PrimitiveType{Kind: domain.Char}
	}

	c.addDiagnostic(UnknownType("Basics."+localName, c.stepName))
	return nil
}

func (c *fromIRConverter) externalTypeToWIT(externalType typemap.TypeID) domain.Type {
	switch externalType {
	case "bool":
		return domain.PrimitiveType{Kind: domain.Bool}
	case "u8":
		return domain.PrimitiveType{Kind: domain.U8}
	case "u16":
		return domain.PrimitiveType{Kind: domain.U16}
	case "u32":
		return domain.PrimitiveType{Kind: domain.U32}
	case "u64":
		return domain.PrimitiveType{Kind: domain.U64}
	case "s8":
		return domain.PrimitiveType{Kind: domain.S8}
	case "s16":
		return domain.PrimitiveType{Kind: domain.S16}
	case "s32":
		return domain.PrimitiveType{Kind: domain.S32}
	case "s64":
		return domain.PrimitiveType{Kind: domain.S64}
	case "f32":
		return domain.PrimitiveType{Kind: domain.F32}
	case "f64":
		return domain.PrimitiveType{Kind: domain.F64}
	case "string":
		return domain.PrimitiveType{Kind: domain.String}
	case "char":
		return domain.PrimitiveType{Kind: domain.Char}
	default:
		return nil
	}
}

// Helper functions

// isEnum checks if all constructors have no arguments (enum-like)
func isEnum(ctors ir.TypeConstructors[any]) bool {
	for _, ctor := range ctors {
		if len(ctor.Args()) > 0 {
			return false
		}
	}
	return true
}

// isUnit checks if a type is the unit type
func isUnit(t ir.Type[any]) bool {
	_, ok := t.(ir.TypeUnit[any])
	return ok
}

// isSDKType checks if a package path is the Morphir SDK
func isSDKType(packagePath ir.Path) bool {
	parts := packagePath.Parts()
	if len(parts) >= 2 {
		return nameToString(parts[0]) == "Morphir" && nameToString(parts[1]) == "SDK"
	}
	return false
}

// nameToString converts an ir.Name to a string.
// Uses ToTitleCase for type/module names (PascalCase convention).
func nameToString(n ir.Name) string {
	return n.ToTitleCase()
}

// toKebabCase converts a PascalCase or camelCase string to kebab-case
func toKebabCase(s string) string {
	var result strings.Builder
	for i, r := range s {
		if i > 0 && r >= 'A' && r <= 'Z' {
			result.WriteRune('-')
		}
		result.WriteRune(r)
	}
	return strings.ToLower(result.String())
}
