package decorations

import (
	"testing"

	ir "github.com/finos/morphir/pkg/models/ir"
	decorationmodels "github.com/finos/morphir/pkg/models/ir/decorations"
)

func TestTypeChecker_UnitType(t *testing.T) {
	// Create a decoration IR with a unit type alias
	pkgName := ir.PathFromString("My.Decoration")
	typeName := ir.NameFromParts([]string{"shape"})
	typeDef := ir.NewTypeAliasDefinition(
		[]ir.Name{},
		ir.NewTypeUnit[ir.Unit](ir.Unit{}),
	)

	modDef := ir.NewModuleDefinition[ir.Unit, ir.Type[ir.Unit]](
		[]ir.ModuleDefinitionType[ir.Unit]{
			ir.ModuleDefinitionTypeFromParts[ir.Unit](
				typeName,
				ir.Public(ir.NewDocumented("Shape type", typeDef)),
			),
		},
		nil,
		nil,
	)

	moduleName := ir.PathFromString("Foo")
	pkgDef := ir.NewPackageDefinition([]ir.PackageDefinitionModule[ir.Unit, ir.Type[ir.Unit]]{
		ir.PackageDefinitionModuleFromParts[ir.Unit, ir.Type[ir.Unit]](
			moduleName,
			ir.Public(modDef),
		),
	})

	lib := ir.NewLibrary(pkgName, nil, pkgDef)
	decIR := decorationmodels.NewDecorationIR(lib, "test.json")
	entryPoint := "My.Decoration:Foo:shape"

	typeChecker, err := NewTypeChecker(decIR, entryPoint)
	if err != nil {
		t.Fatalf("NewTypeChecker: %v", err)
	}

	// Create a unit value
	unitValue := ir.NewUnitValue[ir.Unit, ir.Unit](ir.Unit{})

	// Should pass type checking
	if err := typeChecker.CheckValueType(unitValue); err != nil {
		t.Errorf("CheckValueType: unexpected error: %v", err)
	}
}

func TestTypeChecker_StringLiteral(t *testing.T) {
	// Create a decoration IR with a string type alias
	pkgName := ir.PathFromString("My.Decoration")
	typeName := ir.NameFromParts([]string{"label"})
	stringType := ir.NewTypeReference[ir.Unit](ir.Unit{}, ir.FQNameFromParts(
		ir.PathFromString("Morphir.SDK"),
		ir.PathFromString("String"),
		ir.NameFromParts([]string{"string"}),
	), nil)
	typeDef := ir.NewTypeAliasDefinition(
		[]ir.Name{},
		stringType,
	)

	modDef := ir.NewModuleDefinition[ir.Unit, ir.Type[ir.Unit]](
		[]ir.ModuleDefinitionType[ir.Unit]{
			ir.ModuleDefinitionTypeFromParts[ir.Unit](
				typeName,
				ir.Public(ir.NewDocumented("Label type", typeDef)),
			),
		},
		nil,
		nil,
	)

	moduleName := ir.PathFromString("Foo")
	pkgDef := ir.NewPackageDefinition([]ir.PackageDefinitionModule[ir.Unit, ir.Type[ir.Unit]]{
		ir.PackageDefinitionModuleFromParts[ir.Unit, ir.Type[ir.Unit]](
			moduleName,
			ir.Public(modDef),
		),
	})

	lib := ir.NewLibrary(pkgName, nil, pkgDef)
	decIR := decorationmodels.NewDecorationIR(lib, "test.json")
	entryPoint := "My.Decoration:Foo:label"

	typeChecker, err := NewTypeChecker(decIR, entryPoint)
	if err != nil {
		t.Fatalf("NewTypeChecker: %v", err)
	}

	// Create a string literal value
	stringValue := ir.NewLiteralValue[ir.Unit, ir.Unit](ir.Unit{}, ir.NewStringLiteral("hello"))

	// Should pass type checking
	if err := typeChecker.CheckValueType(stringValue); err != nil {
		t.Errorf("CheckValueType: unexpected error: %v", err)
	}
}

func TestTypeChecker_RecordType(t *testing.T) {
	// Create a decoration IR with a record type
	pkgName := ir.PathFromString("My.Decoration")
	typeName := ir.NameFromParts([]string{"metadata"})
	
	// Record type: { name: String, value: Int }
	recordFields := []ir.Field[ir.Unit]{
		ir.FieldFromParts[ir.Unit](
			ir.NameFromParts([]string{"name"}),
			ir.NewTypeReference[ir.Unit](ir.Unit{}, ir.FQNameFromParts(
				ir.PathFromString("Morphir.SDK"),
				ir.PathFromString("String"),
				ir.NameFromParts([]string{"string"}),
			), nil),
		),
		ir.FieldFromParts[ir.Unit](
			ir.NameFromParts([]string{"value"}),
			ir.NewTypeReference[ir.Unit](ir.Unit{}, ir.FQNameFromParts(
				ir.PathFromString("Morphir.SDK"),
				ir.PathFromString("Basics"),
				ir.NameFromParts([]string{"int"}),
			), nil),
		),
	}
	recordType := ir.NewTypeRecord[ir.Unit](ir.Unit{}, recordFields)
	typeDef := ir.NewTypeAliasDefinition(
		[]ir.Name{},
		recordType,
	)

	modDef := ir.NewModuleDefinition[ir.Unit, ir.Type[ir.Unit]](
		[]ir.ModuleDefinitionType[ir.Unit]{
			ir.ModuleDefinitionTypeFromParts[ir.Unit](
				typeName,
				ir.Public(ir.NewDocumented("Metadata type", typeDef)),
			),
		},
		nil,
		nil,
	)

	moduleName := ir.PathFromString("Foo")
	pkgDef := ir.NewPackageDefinition([]ir.PackageDefinitionModule[ir.Unit, ir.Type[ir.Unit]]{
		ir.PackageDefinitionModuleFromParts[ir.Unit, ir.Type[ir.Unit]](
			moduleName,
			ir.Public(modDef),
		),
	})

	lib := ir.NewLibrary(pkgName, nil, pkgDef)
	decIR := decorationmodels.NewDecorationIR(lib, "test.json")
	entryPoint := "My.Decoration:Foo:metadata"

	typeChecker, err := NewTypeChecker(decIR, entryPoint)
	if err != nil {
		t.Fatalf("NewTypeChecker: %v", err)
	}

	// Create a record value matching the type
	recordFieldsValue := []ir.RecordField[ir.Unit, ir.Unit]{
		ir.RecordFieldFromParts[ir.Unit, ir.Unit](
			ir.NameFromParts([]string{"name"}),
			ir.NewLiteralValue[ir.Unit, ir.Unit](ir.Unit{}, ir.NewStringLiteral("test")),
		),
		ir.RecordFieldFromParts[ir.Unit, ir.Unit](
			ir.NameFromParts([]string{"value"}),
			ir.NewLiteralValue[ir.Unit, ir.Unit](ir.Unit{}, ir.NewWholeNumberLiteral(42)),
		),
	}
	recordValue := ir.NewRecordValue[ir.Unit, ir.Unit](ir.Unit{}, recordFieldsValue)

	// Should pass type checking
	if err := typeChecker.CheckValueType(recordValue); err != nil {
		t.Errorf("CheckValueType: unexpected error: %v", err)
	}
}

func TestInferLiteralType(t *testing.T) {
	tests := []struct {
		name    string
		literal ir.Literal
	}{
		{"Bool", ir.NewBoolLiteral(true)},
		{"String", ir.NewStringLiteral("hello")},
		{"Int", ir.NewWholeNumberLiteral(42)},
		{"Float", ir.NewFloatLiteral(3.14)},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := inferLiteralType(tt.literal)
			if got == nil {
				t.Fatal("inferLiteralType returned nil")
			}
			// Just verify it's a TypeReference for SDK types
			if _, ok := got.(ir.TypeReference[ir.Unit]); !ok {
				t.Errorf("expected TypeReference, got %T", got)
			}
		})
	}
}
