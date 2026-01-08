package pipeline_test

import (
	"testing"

	"github.com/finos/morphir/pkg/bindings/wit/domain"
	"github.com/finos/morphir/pkg/bindings/wit/pipeline"
	"github.com/finos/morphir/pkg/models/ir"
)

func TestConvertFromIR_BasicTypes(t *testing.T) {
	// Create a simple module with basic types
	module := makeIRModuleWithType("test-type", makeBasicsTypeRef("Bool"))

	pkg, diagnostics := pipeline.ConvertFromIR(module, pipeline.GenOptions{})

	// Should not have errors
	if pipeline.HasErrors(diagnostics) {
		t.Errorf("unexpected errors: %v", diagnostics)
	}

	// Should have interfaces
	if len(pkg.Interfaces) != 1 {
		t.Errorf("expected 1 interface, got %d", len(pkg.Interfaces))
	}
}

func TestConvertFromIR_RecordType(t *testing.T) {
	// Create a record type
	fields := []ir.Field[any]{
		ir.FieldFromParts(ir.NameFromString("x"), makeBasicsTypeRef("Int")),
		ir.FieldFromParts(ir.NameFromString("y"), makeBasicsTypeRef("Int")),
	}
	recordType := ir.NewTypeRecord[any](nil, fields)

	// Wrap in type alias definition
	typeAlias := ir.NewTypeAliasDefinition[any](nil, recordType)
	documented := ir.NewDocumented[ir.TypeDefinition[any]]("", typeAlias)
	acl := ir.NewAccessControlled(ir.AccessPublic, documented)
	modType := ir.ModuleDefinitionTypeFromParts[any](ir.NameFromString("Point"), acl)

	module := ir.NewModuleDefinition[any, any](
		[]ir.ModuleDefinitionType[any]{modType},
		nil,
		nil,
	)

	pkg, diagnostics := pipeline.ConvertFromIR(module, pipeline.GenOptions{})

	// Info diagnostics for Int -> s32 default are expected, not warnings
	_ = diagnostics

	// Should have one interface with one type
	if len(pkg.Interfaces) != 1 {
		t.Errorf("expected 1 interface, got %d", len(pkg.Interfaces))
	}

	iface := pkg.Interfaces[0]
	if len(iface.Types) != 1 {
		t.Errorf("expected 1 type, got %d", len(iface.Types))
	}

	// Check it's a record
	typeDef := iface.Types[0]
	if _, ok := typeDef.Kind.(domain.RecordDef); !ok {
		t.Errorf("expected RecordDef, got %T", typeDef.Kind)
	}
}

func TestConvertFromIR_EnumType(t *testing.T) {
	// Create an enum type (custom type with no-arg constructors)
	ctors := ir.TypeConstructors[any]{
		ir.TypeConstructorFromParts[any](ir.NameFromString("Red"), nil),
		ir.TypeConstructorFromParts[any](ir.NameFromString("Green"), nil),
		ir.TypeConstructorFromParts[any](ir.NameFromString("Blue"), nil),
	}
	ctorsACL := ir.NewAccessControlled(ir.AccessPublic, ctors)
	customType := ir.NewCustomTypeDefinition[any](nil, ctorsACL)
	documented := ir.NewDocumented[ir.TypeDefinition[any]]("", customType)
	acl := ir.NewAccessControlled(ir.AccessPublic, documented)
	modType := ir.ModuleDefinitionTypeFromParts[any](ir.NameFromString("Color"), acl)

	module := ir.NewModuleDefinition[any, any](
		[]ir.ModuleDefinitionType[any]{modType},
		nil,
		nil,
	)

	pkg, diagnostics := pipeline.ConvertFromIR(module, pipeline.GenOptions{})

	// Should not have errors
	if pipeline.HasErrors(diagnostics) {
		t.Errorf("unexpected errors: %v", diagnostics)
	}

	// Check it's an enum
	iface := pkg.Interfaces[0]
	typeDef := iface.Types[0]
	enumDef, ok := typeDef.Kind.(domain.EnumDef)
	if !ok {
		t.Errorf("expected EnumDef, got %T", typeDef.Kind)
		return
	}

	if len(enumDef.Cases) != 3 {
		t.Errorf("expected 3 enum cases, got %d", len(enumDef.Cases))
	}
}

func TestConvertFromIR_VariantType(t *testing.T) {
	// Create a variant type (custom type with some constructors having args)
	ctors := ir.TypeConstructors[any]{
		ir.TypeConstructorFromParts[any](
			ir.NameFromString("Ok"),
			ir.TypeConstructorArgs[any]{
				ir.TypeConstructorArgFromParts[any](
					ir.NameFromString("value"),
					makeBasicsTypeRef("String"),
				),
			},
		),
		ir.TypeConstructorFromParts[any](
			ir.NameFromString("Err"),
			ir.TypeConstructorArgs[any]{
				ir.TypeConstructorArgFromParts[any](
					ir.NameFromString("value"),
					makeBasicsTypeRef("Int"),
				),
			},
		),
	}
	ctorsACL := ir.NewAccessControlled(ir.AccessPublic, ctors)
	customType := ir.NewCustomTypeDefinition[any](nil, ctorsACL)
	documented := ir.NewDocumented[ir.TypeDefinition[any]]("", customType)
	acl := ir.NewAccessControlled(ir.AccessPublic, documented)
	modType := ir.ModuleDefinitionTypeFromParts[any](ir.NameFromString("MyResult"), acl)

	module := ir.NewModuleDefinition[any, any](
		[]ir.ModuleDefinitionType[any]{modType},
		nil,
		nil,
	)

	pkg, diagnostics := pipeline.ConvertFromIR(module, pipeline.GenOptions{})

	// Should have info diagnostics for Int -> s32 default
	// (not checking for errors since Int -> s32 emits Info, not Error)
	_ = diagnostics

	// Check it's a variant
	iface := pkg.Interfaces[0]
	typeDef := iface.Types[0]
	variantDef, ok := typeDef.Kind.(domain.VariantDef)
	if !ok {
		t.Errorf("expected VariantDef, got %T", typeDef.Kind)
		return
	}

	if len(variantDef.Cases) != 2 {
		t.Errorf("expected 2 variant cases, got %d", len(variantDef.Cases))
	}

	// Check that cases have payloads
	for _, c := range variantDef.Cases {
		if c.Payload == nil {
			t.Errorf("expected payload for case %s", c.Name)
		}
	}
}

func TestConvertFromIR_Function(t *testing.T) {
	// Create a function value definition
	inputs := []ir.ValueDefinitionInput[any, any]{
		ir.ValueDefinitionInputFromParts[any, any](
			ir.NameFromString("a"),
			nil,
			makeBasicsTypeRef("Int"),
		),
		ir.ValueDefinitionInputFromParts[any, any](
			ir.NameFromString("b"),
			nil,
			makeBasicsTypeRef("Int"),
		),
	}
	outputType := makeBasicsTypeRef("Int")
	valueDef := ir.NewValueDefinition[any, any](inputs, outputType, nil)
	documented := ir.NewDocumented("", valueDef)
	acl := ir.NewAccessControlled(ir.AccessPublic, documented)
	modValue := ir.ModuleDefinitionValueFromParts(ir.NameFromString("add"), acl)

	module := ir.NewModuleDefinition[any, any](
		nil,
		[]ir.ModuleDefinitionValue[any, any]{modValue},
		nil,
	)

	pkg, diagnostics := pipeline.ConvertFromIR(module, pipeline.GenOptions{})

	// Should have info diagnostics for Int -> s32 default
	_ = diagnostics

	// Check we have a function
	iface := pkg.Interfaces[0]
	if len(iface.Functions) != 1 {
		t.Errorf("expected 1 function, got %d", len(iface.Functions))
		return
	}

	fn := iface.Functions[0]
	if len(fn.Params) != 2 {
		t.Errorf("expected 2 params, got %d", len(fn.Params))
	}
	if len(fn.Results) != 1 {
		t.Errorf("expected 1 result, got %d", len(fn.Results))
	}
}

func TestConvertFromIR_ContainerTypes(t *testing.T) {
	tests := []struct {
		name     string
		irType   ir.Type[any]
		checkWIT func(domain.Type) bool
	}{
		{
			name:   "list",
			irType: makeSDKTypeRef("List", "List", makeBasicsTypeRef("String")),
			checkWIT: func(t domain.Type) bool {
				_, ok := t.(domain.ListType)
				return ok
			},
		},
		{
			name:   "option",
			irType: makeSDKTypeRef("Maybe", "Maybe", makeBasicsTypeRef("String")),
			checkWIT: func(t domain.Type) bool {
				_, ok := t.(domain.OptionType)
				return ok
			},
		},
		{
			name:   "result",
			irType: makeSDKTypeRef("Result", "Result", makeBasicsTypeRef("String"), makeBasicsTypeRef("Int")),
			checkWIT: func(t domain.Type) bool {
				_, ok := t.(domain.ResultType)
				return ok
			},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			module := makeIRModuleWithFunction("test-func", tt.irType)
			pkg, _ := pipeline.ConvertFromIR(module, pipeline.GenOptions{})

			if len(pkg.Interfaces) != 1 || len(pkg.Interfaces[0].Functions) != 1 {
				t.Fatal("expected 1 function in 1 interface")
			}

			fn := pkg.Interfaces[0].Functions[0]
			if len(fn.Results) != 1 {
				t.Fatal("expected 1 result")
			}

			if !tt.checkWIT(fn.Results[0]) {
				t.Errorf("expected %s type, got %T", tt.name, fn.Results[0])
			}
		})
	}
}

func TestConvertFromIR_ToKebabCase(t *testing.T) {
	// Create a type with PascalCase name
	typeAlias := ir.NewTypeAliasDefinition[any](nil, makeBasicsTypeRef("String"))
	documented := ir.NewDocumented[ir.TypeDefinition[any]]("", typeAlias)
	acl := ir.NewAccessControlled(ir.AccessPublic, documented)
	modType := ir.ModuleDefinitionTypeFromParts[any](ir.NameFromString("MyTypeName"), acl)

	module := ir.NewModuleDefinition[any, any](
		[]ir.ModuleDefinitionType[any]{modType},
		nil,
		nil,
	)

	pkg, _ := pipeline.ConvertFromIR(module, pipeline.GenOptions{})

	typeDef := pkg.Interfaces[0].Types[0]
	// Should be converted to kebab-case
	expected := "my-type-name"
	if typeDef.Name.String() != expected {
		t.Errorf("expected kebab-case name %q, got %q", expected, typeDef.Name.String())
	}
}

func TestConvertFromIR_EmptyModule(t *testing.T) {
	module := ir.NewModuleDefinition[any, any](nil, nil, nil)

	pkg, diagnostics := pipeline.ConvertFromIR(module, pipeline.GenOptions{})

	if pipeline.HasErrors(diagnostics) {
		t.Errorf("unexpected errors: %v", diagnostics)
	}

	// Should still have one interface (generated)
	if len(pkg.Interfaces) != 1 {
		t.Errorf("expected 1 interface, got %d", len(pkg.Interfaces))
	}
}

// Helper functions

func makeBasicsTypeRef(typeName string) ir.Type[any] {
	return ir.NewTypeReference[any](
		nil,
		ir.FQNameFromParts(
			ir.PathFromParts([]ir.Name{ir.NameFromString("Morphir"), ir.NameFromString("SDK")}),
			ir.PathFromParts([]ir.Name{ir.NameFromString("Basics")}),
			ir.NameFromString(typeName),
		),
		nil,
	)
}

func makeSDKTypeRef(moduleName, typeName string, typeParams ...ir.Type[any]) ir.Type[any] {
	return ir.NewTypeReference[any](
		nil,
		ir.FQNameFromParts(
			ir.PathFromParts([]ir.Name{ir.NameFromString("Morphir"), ir.NameFromString("SDK")}),
			ir.PathFromParts([]ir.Name{ir.NameFromString(moduleName)}),
			ir.NameFromString(typeName),
		),
		typeParams,
	)
}

func makeIRModuleWithType(typeName string, typeExpr ir.Type[any]) ir.ModuleDefinition[any, any] {
	typeAlias := ir.NewTypeAliasDefinition[any](nil, typeExpr)
	documented := ir.NewDocumented[ir.TypeDefinition[any]]("", typeAlias)
	acl := ir.NewAccessControlled(ir.AccessPublic, documented)
	modType := ir.ModuleDefinitionTypeFromParts[any](ir.NameFromString(typeName), acl)

	return ir.NewModuleDefinition[any, any](
		[]ir.ModuleDefinitionType[any]{modType},
		nil,
		nil,
	)
}

func makeIRModuleWithFunction(funcName string, resultType ir.Type[any]) ir.ModuleDefinition[any, any] {
	valueDef := ir.NewValueDefinition[any, any](nil, resultType, nil)
	documented := ir.NewDocumented("", valueDef)
	acl := ir.NewAccessControlled(ir.AccessPublic, documented)
	modValue := ir.ModuleDefinitionValueFromParts(ir.NameFromString(funcName), acl)

	return ir.NewModuleDefinition[any, any](
		nil,
		[]ir.ModuleDefinitionValue[any, any]{modValue},
		nil,
	)
}
