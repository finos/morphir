package pipeline

import (
	"fmt"

	"github.com/finos/morphir/pkg/bindings/typemap"
	"github.com/finos/morphir/pkg/bindings/wit"
	"github.com/finos/morphir/pkg/bindings/wit/domain"
	"github.com/finos/morphir/pkg/models/ir"
	"github.com/finos/morphir/pkg/pipeline"
)

// ConvertToIR converts a WIT domain.Package to a Morphir IR ModuleDefinition.
// It returns the converted module and any diagnostics generated during conversion.
func ConvertToIR(pkg domain.Package, opts MakeOptions) (ir.ModuleDefinition[SourceLocation, SourceLocation], []pipeline.Diagnostic) {
	c := &toIRConverter{
		registry: wit.DefaultWITRegistry(),
		opts:     opts,
		stepName: "wit-make",
	}
	return c.convert(pkg)
}

// toIRConverter handles the conversion from WIT to Morphir IR.
type toIRConverter struct {
	registry    *typemap.Registry
	opts        MakeOptions
	stepName    string
	diagnostics []pipeline.Diagnostic
}

func (c *toIRConverter) addDiagnostic(d pipeline.Diagnostic) {
	c.diagnostics = append(c.diagnostics, d)
}

func (c *toIRConverter) convert(pkg domain.Package) (ir.ModuleDefinition[SourceLocation, SourceLocation], []pipeline.Diagnostic) {
	var types []ir.ModuleDefinitionType[SourceLocation]
	var values []ir.ModuleDefinitionValue[SourceLocation, SourceLocation]

	// Convert interfaces to module types/values
	for _, iface := range pkg.Interfaces {
		ifaceTypes, ifaceValues := c.convertInterface(iface)
		types = append(types, ifaceTypes...)
		values = append(values, ifaceValues...)
	}

	// Convert worlds - treat exports/imports as additional types/values
	for _, world := range pkg.Worlds {
		worldTypes, worldValues := c.convertWorld(world)
		types = append(types, worldTypes...)
		values = append(values, worldValues...)
	}

	// Get documentation
	var doc *string
	if !pkg.Docs.IsEmpty() {
		s := pkg.Docs.String()
		doc = &s
	}

	return ir.NewModuleDefinition(types, values, doc), c.diagnostics
}

func (c *toIRConverter) convertInterface(iface domain.Interface) ([]ir.ModuleDefinitionType[SourceLocation], []ir.ModuleDefinitionValue[SourceLocation, SourceLocation]) {
	var types []ir.ModuleDefinitionType[SourceLocation]
	var values []ir.ModuleDefinitionValue[SourceLocation, SourceLocation]

	// Convert type definitions
	for _, td := range iface.Types {
		if t := c.convertTypeDef(td); t != nil {
			types = append(types, *t)
		}
	}

	// Convert functions to value definitions
	for _, fn := range iface.Functions {
		if v := c.convertFunction(fn); v != nil {
			values = append(values, *v)
		}
	}

	return types, values
}

func (c *toIRConverter) convertWorld(world domain.World) ([]ir.ModuleDefinitionType[SourceLocation], []ir.ModuleDefinitionValue[SourceLocation, SourceLocation]) {
	var types []ir.ModuleDefinitionType[SourceLocation]
	var values []ir.ModuleDefinitionValue[SourceLocation, SourceLocation]

	// Process imports
	for _, item := range world.Imports {
		itemTypes, itemValues := c.convertWorldItem(item)
		types = append(types, itemTypes...)
		values = append(values, itemValues...)
	}

	// Process exports
	for _, item := range world.Exports {
		itemTypes, itemValues := c.convertWorldItem(item)
		types = append(types, itemTypes...)
		values = append(values, itemValues...)
	}

	return types, values
}

func (c *toIRConverter) convertWorldItem(item domain.WorldItem) ([]ir.ModuleDefinitionType[SourceLocation], []ir.ModuleDefinitionValue[SourceLocation, SourceLocation]) {
	var types []ir.ModuleDefinitionType[SourceLocation]
	var values []ir.ModuleDefinitionValue[SourceLocation, SourceLocation]

	switch it := item.(type) {
	case domain.InterfaceItem:
		// For interface items, check if it's an inline interface
		switch ref := it.Ref.(type) {
		case domain.InlineInterface:
			ifaceTypes, ifaceValues := c.convertInterface(ref.Interface)
			types = append(types, ifaceTypes...)
			values = append(values, ifaceValues...)
		case domain.ExternalInterfaceRef:
			// External references - we don't have the interface definition here
			// Just emit a diagnostic for now
			c.addDiagnostic(DiagnosticInfo(
				"WIT_EXTERNAL_REF",
				fmt.Sprintf("external interface reference: %v", ref.Path),
				c.stepName,
			))
		}
	case domain.FunctionItem:
		if v := c.convertFunction(it.Func); v != nil {
			values = append(values, *v)
		}
	}

	return types, values
}

func (c *toIRConverter) convertTypeDef(td domain.TypeDef) *ir.ModuleDefinitionType[SourceLocation] {
	name := ir.NameFromString(td.Name.String())

	var typeSpec ir.TypeDefinition[SourceLocation]

	switch kind := td.Kind.(type) {
	case domain.RecordDef:
		typeSpec = c.convertRecordDef(kind)

	case domain.VariantDef:
		typeSpec = c.convertVariantDef(td.Name.String(), kind)

	case domain.EnumDef:
		typeSpec = c.convertEnumDef(td.Name.String(), kind)

	case domain.FlagsDef:
		// Flags are not directly supported
		c.addDiagnostic(FlagsUnsupported(td.Name.String(), c.stepName, c.opts.StrictMode))
		if c.opts.StrictMode {
			return nil
		}
		// Fallback: treat as type alias to Int (bitmask representation)
		typeSpec = ir.NewTypeAliasDefinition[SourceLocation](
			nil,
			c.makeSDKTypeRef("Int"),
		)

	case domain.ResourceDef:
		// Resources are not directly supported
		c.addDiagnostic(ResourceUnsupported(td.Name.String(), c.stepName, c.opts.StrictMode))
		if c.opts.StrictMode {
			return nil
		}
		// Fallback: treat as opaque type (type alias)
		typeSpec = ir.NewTypeAliasDefinition[SourceLocation](
			nil,
			c.makeSDKTypeRef("Int"),
		)

	case domain.TypeAliasDef:
		irType := c.convertType(kind.Target)
		typeSpec = ir.NewTypeAliasDefinition[SourceLocation](nil, irType)

	default:
		c.addDiagnostic(ConversionError(
			fmt.Sprintf("unknown type definition kind: %T", td.Kind),
			c.stepName,
		))
		return nil
	}

	// Wrap in documentation
	var doc string
	if !td.Docs.IsEmpty() {
		doc = td.Docs.String()
	}
	documented := ir.NewDocumented(doc, typeSpec)

	// Wrap in access control (public by default)
	acl := ir.NewAccessControlled(ir.AccessPublic, documented)

	return ptrTo(ir.ModuleDefinitionTypeFromParts[SourceLocation](name, acl))
}

func (c *toIRConverter) convertRecordDef(rd domain.RecordDef) ir.TypeDefinition[SourceLocation] {
	var fields []ir.Field[SourceLocation]
	for _, f := range rd.Fields {
		fieldType := c.convertType(f.Type)
		fieldName := ir.NameFromString(f.Name.String())
		fields = append(fields, ir.FieldFromParts(fieldName, fieldType))
	}
	return ir.NewTypeAliasDefinition[SourceLocation](
		nil,
		ir.NewTypeRecord(SourceLocation{}, fields),
	)
}

func (c *toIRConverter) convertVariantDef(name string, vd domain.VariantDef) ir.TypeDefinition[SourceLocation] {
	var constructors ir.TypeConstructors[SourceLocation]
	for _, vc := range vd.Cases {
		ctorName := ir.NameFromString(vc.Name.String())
		var args ir.TypeConstructorArgs[SourceLocation]
		if vc.Payload != nil {
			argType := c.convertType(*vc.Payload)
			args = ir.TypeConstructorArgs[SourceLocation]{
				ir.TypeConstructorArgFromParts(ir.NameFromString("value"), argType),
			}
		}
		constructors = append(constructors, ir.TypeConstructorFromParts(ctorName, args))
	}
	return ir.NewCustomTypeDefinition[SourceLocation](nil, ir.NewAccessControlled(
		ir.AccessPublic,
		constructors,
	))
}

func (c *toIRConverter) convertEnumDef(name string, ed domain.EnumDef) ir.TypeDefinition[SourceLocation] {
	var constructors ir.TypeConstructors[SourceLocation]
	for _, caseName := range ed.Cases {
		ctorName := ir.NameFromString(caseName.String())
		constructors = append(constructors, ir.TypeConstructorFromParts[SourceLocation](ctorName, nil))
	}
	return ir.NewCustomTypeDefinition[SourceLocation](nil, ir.NewAccessControlled(
		ir.AccessPublic,
		constructors,
	))
}

func (c *toIRConverter) convertFunction(fn domain.Function) *ir.ModuleDefinitionValue[SourceLocation, SourceLocation] {
	name := ir.NameFromString(fn.Name.String())

	// Determine result type
	var outputType ir.Type[SourceLocation]
	if len(fn.Results) == 0 {
		outputType = ir.NewTypeUnit[SourceLocation](SourceLocation{})
	} else if len(fn.Results) == 1 {
		outputType = c.convertType(fn.Results[0])
	} else {
		// Multiple results become a tuple
		var elements []ir.Type[SourceLocation]
		for _, r := range fn.Results {
			elements = append(elements, c.convertType(r))
		}
		outputType = ir.NewTypeTuple(SourceLocation{}, elements)
	}

	// Create input types for value definition
	var inputTypes []ir.ValueDefinitionInput[SourceLocation, SourceLocation]
	for _, p := range fn.Params {
		paramType := c.convertType(p.Type)
		paramName := ir.NameFromString(p.Name.String())
		inputTypes = append(inputTypes, ir.ValueDefinitionInputFromParts(paramName, SourceLocation{}, paramType))
	}

	// Create value definition (no body - WIT functions are declarations only)
	valueDef := ir.NewValueDefinition[SourceLocation, SourceLocation](inputTypes, outputType, nil)

	// Wrap in documentation
	var doc string
	if !fn.Docs.IsEmpty() {
		doc = fn.Docs.String()
	}

	documented := ir.NewDocumented(doc, valueDef)
	acl := ir.NewAccessControlled(ir.AccessPublic, documented)

	return ptrTo(ir.ModuleDefinitionValueFromParts[SourceLocation, SourceLocation](name, acl))
}

func (c *toIRConverter) convertType(t domain.Type) ir.Type[SourceLocation] {
	if t == nil {
		return ir.NewTypeUnit[SourceLocation](SourceLocation{})
	}

	switch ty := t.(type) {
	case domain.PrimitiveType:
		return c.convertPrimitiveType(ty)

	case domain.NamedType:
		// Reference to a user-defined type
		return ir.NewTypeVariable[SourceLocation](SourceLocation{}, ir.NameFromString(ty.Name.String()))

	case domain.ListType:
		elemType := c.convertType(ty.Element)
		return ir.NewTypeReference(
			SourceLocation{},
			c.makeSDKFQName("List", "List"),
			[]ir.Type[SourceLocation]{elemType},
		)

	case domain.OptionType:
		innerType := c.convertType(ty.Inner)
		return ir.NewTypeReference(
			SourceLocation{},
			c.makeSDKFQName("Maybe", "Maybe"),
			[]ir.Type[SourceLocation]{innerType},
		)

	case domain.ResultType:
		var okType, errType ir.Type[SourceLocation]
		if ty.Ok != nil {
			okType = c.convertType(*ty.Ok)
		} else {
			okType = ir.NewTypeUnit[SourceLocation](SourceLocation{})
		}
		if ty.Err != nil {
			errType = c.convertType(*ty.Err)
		} else {
			errType = ir.NewTypeUnit[SourceLocation](SourceLocation{})
		}
		// Morphir Result has error type first: Result E T
		return ir.NewTypeReference(
			SourceLocation{},
			c.makeSDKFQName("Result", "Result"),
			[]ir.Type[SourceLocation]{errType, okType},
		)

	case domain.TupleType:
		var elements []ir.Type[SourceLocation]
		for _, elem := range ty.Types {
			elements = append(elements, c.convertType(elem))
		}
		return ir.NewTypeTuple(SourceLocation{}, elements)

	case domain.HandleType:
		// Handles are not directly supported
		c.addDiagnostic(ResourceUnsupported(ty.Resource.String(), c.stepName, c.opts.StrictMode))
		// Fallback to Int (handle is an opaque integer)
		return c.makeSDKTypeRef("Int")

	case domain.FutureType:
		// Future types are not supported (WASI Preview 3)
		c.addDiagnostic(DiagnosticWarn(
			CodeConversionError,
			"future type not supported, using inner type",
			c.stepName,
		))
		if ty.Inner != nil {
			return c.convertType(*ty.Inner)
		}
		return ir.NewTypeUnit[SourceLocation](SourceLocation{})

	case domain.StreamType:
		// Stream types are not supported (WASI Preview 3)
		c.addDiagnostic(DiagnosticWarn(
			CodeConversionError,
			"stream type not supported, using List of element type",
			c.stepName,
		))
		if ty.Element != nil {
			elemType := c.convertType(*ty.Element)
			return ir.NewTypeReference(
				SourceLocation{},
				c.makeSDKFQName("List", "List"),
				[]ir.Type[SourceLocation]{elemType},
			)
		}
		return ir.NewTypeReference(
			SourceLocation{},
			c.makeSDKFQName("List", "List"),
			[]ir.Type[SourceLocation]{ir.NewTypeUnit[SourceLocation](SourceLocation{})},
		)

	default:
		c.addDiagnostic(UnknownType(fmt.Sprintf("%T", t), c.stepName))
		return ir.NewTypeUnit[SourceLocation](SourceLocation{})
	}
}

func (c *toIRConverter) convertPrimitiveType(pt domain.PrimitiveType) ir.Type[SourceLocation] {
	// Map primitive kind to external type ID
	var externalTypeID typemap.TypeID
	switch pt.Kind {
	case domain.U8:
		externalTypeID = "u8"
	case domain.U16:
		externalTypeID = "u16"
	case domain.U32:
		externalTypeID = "u32"
	case domain.U64:
		externalTypeID = "u64"
	case domain.S8:
		externalTypeID = "s8"
	case domain.S16:
		externalTypeID = "s16"
	case domain.S32:
		externalTypeID = "s32"
	case domain.S64:
		externalTypeID = "s64"
	case domain.F32:
		externalTypeID = "f32"
	case domain.F64:
		externalTypeID = "f64"
	case domain.Bool:
		externalTypeID = "bool"
	case domain.Char:
		externalTypeID = "char"
	case domain.String:
		externalTypeID = "string"
	default:
		c.addDiagnostic(UnknownType(fmt.Sprintf("primitive:%d", pt.Kind), c.stepName))
		return ir.NewTypeUnit[SourceLocation](SourceLocation{})
	}

	// Look up in registry
	mapping, ok := c.registry.Lookup(externalTypeID)
	if !ok {
		c.addDiagnostic(UnknownType(string(externalTypeID), c.stepName))
		return ir.NewTypeUnit[SourceLocation](SourceLocation{})
	}

	// Check for lossy integer mapping
	// All WIT integer types (u8/u16/u32/u64/s8/s16/s32/s64) lose size/signedness info when mapped to Int
	if isIntegerType(pt.Kind) {
		c.addDiagnostic(IntPrecisionLost(string(externalTypeID), c.stepName))
	}

	// Check for float precision loss (f32 → Float loses precision hint)
	if pt.Kind == domain.F32 {
		c.addDiagnostic(FloatPrecisionLost("f32", c.stepName))
	}

	// Convert to IR type based on the mapping
	return c.morphirRefToIRType(mapping.MorphirType)
}

func (c *toIRConverter) morphirRefToIRType(ref typemap.MorphirTypeRef) ir.Type[SourceLocation] {
	if ref.IsPrimitive() {
		return c.makeSDKTypeRef(ref.PrimitiveKind)
	}
	// For FQName references, parse and create type reference
	// For now, just use the primitive kind approach
	return c.makeSDKTypeRef(ref.PrimitiveKind)
}

func (c *toIRConverter) makeSDKTypeRef(typeName string) ir.Type[SourceLocation] {
	return ir.NewTypeReference[SourceLocation](
		SourceLocation{},
		c.makeSDKFQName("Basics", typeName),
		nil,
	)
}

func (c *toIRConverter) makeSDKFQName(moduleName, localName string) ir.FQName {
	return ir.FQNameFromParts(
		ir.PathFromParts([]ir.Name{
			ir.NameFromString("Morphir"),
			ir.NameFromString("SDK"),
		}),
		ir.PathFromParts([]ir.Name{ir.NameFromString(moduleName)}),
		ir.NameFromString(localName),
	)
}

func ptrTo[T any](v T) *T {
	return &v
}

// isIntegerType checks if a WIT primitive kind is an integer type.
// Used to determine if conversion to Morphir Int loses precision/signedness info.
func isIntegerType(kind domain.PrimitiveKind) bool {
	switch kind {
	case domain.U8, domain.U16, domain.U32, domain.U64,
		domain.S8, domain.S16, domain.S32, domain.S64:
		return true
	default:
		return false
	}
}
