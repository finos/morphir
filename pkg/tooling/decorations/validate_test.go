package decorations

import (
	"encoding/json"
	"testing"

	ir "github.com/finos/morphir/pkg/models/ir"
	jsoncodec "github.com/finos/morphir/pkg/models/ir/codec/json"
	decorationmodels "github.com/finos/morphir/pkg/models/ir/decorations"
)

func TestValidateDecorationValue_ValidValue(t *testing.T) {
	// Create a decoration IR
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

	// Create a valid Morphir IR value (unit value)
	opts := jsoncodec.Options{FormatVersion: jsoncodec.FormatV3}
	unitAttr := ir.Unit{}
	unitValue := ir.NewUnitValue[ir.Unit, ir.Unit](unitAttr)

	encodeUnitAttr := func(ir.Unit) (json.RawMessage, error) {
		return json.RawMessage("[]"), nil
	}
	encodeValueUnitAttr := func(ir.Unit) (json.RawMessage, error) {
		return json.RawMessage("[]"), nil
	}

	valueJSON, err := jsoncodec.EncodeValue(opts, encodeUnitAttr, encodeValueUnitAttr, unitValue)
	if err != nil {
		t.Fatalf("EncodeValue: %v", err)
	}

	nodePath := ir.NodePathFromFQName(ir.FQNameFromParts(
		ir.PathFromString("My.Package"),
		ir.PathFromString("Foo"),
		ir.NameFromParts([]string{"bar"}),
	))

	err = ValidateDecorationValue(decIR, entryPoint, nodePath, valueJSON)
	if err != nil {
		t.Errorf("ValidateDecorationValue: unexpected error: %v", err)
	}
}

func TestValidateDecorationValue_InvalidJSON(t *testing.T) {
	lib := ir.NewLibrary(ir.PathFromString("Test"), nil, ir.EmptyPackageDefinition[ir.Unit, ir.Type[ir.Unit]]())
	decIR := decorationmodels.NewDecorationIR(lib, "test.json")
	entryPoint := "Test:Module:Type"

	nodePath := ir.NodePathFromFQName(ir.FQNameFromParts(
		ir.PathFromString("My.Package"),
		ir.PathFromString("Foo"),
		ir.NameFromParts([]string{"bar"}),
	))

	// Invalid JSON
	invalidJSON := json.RawMessage(`{"not": "valid", "morphir": "ir"}`)

	err := ValidateDecorationValue(decIR, entryPoint, nodePath, invalidJSON)
	if err == nil {
		t.Fatal("expected error for invalid JSON")
	}

	valErr, ok := err.(ValidationError)
	if !ok {
		t.Fatalf("expected ValidationError, got %T", err)
	}

	if valErr.NodePath.String() != nodePath.String() {
		t.Errorf("NodePath: got %q, want %q", valErr.NodePath.String(), nodePath.String())
	}
}

func TestValidateDecorationValues_Empty(t *testing.T) {
	lib := ir.NewLibrary(ir.PathFromString("Test"), nil, ir.EmptyPackageDefinition[ir.Unit, ir.Type[ir.Unit]]())
	decIR := decorationmodels.NewDecorationIR(lib, "test.json")
	entryPoint := "Test:Module:Type"

	values := decorationmodels.EmptyDecorationValues()
	result := ValidateDecorationValues(decIR, entryPoint, values)

	if !result.Valid {
		t.Errorf("expected valid result for empty values, got errors: %v", result.Errors)
	}
	if result.Checked != 0 {
		t.Errorf("Checked: got %d, want 0", result.Checked)
	}
	if len(result.Errors) != 0 {
		t.Errorf("expected no errors, got %d", len(result.Errors))
	}
}

func TestValidateDecorationValues_WithErrors(t *testing.T) {
	// Create a proper decoration IR with a type
	pkgName := ir.PathFromString("Test")
	typeName := ir.NameFromParts([]string{"type"})
	typeDef := ir.NewTypeAliasDefinition(
		[]ir.Name{},
		ir.NewTypeUnit[ir.Unit](ir.Unit{}),
	)

	modDef := ir.NewModuleDefinition[ir.Unit, ir.Type[ir.Unit]](
		[]ir.ModuleDefinitionType[ir.Unit]{
			ir.ModuleDefinitionTypeFromParts[ir.Unit](
				typeName,
				ir.Public(ir.NewDocumented("Type", typeDef)),
			),
		},
		nil,
		nil,
	)

	moduleName := ir.PathFromString("Module")
	pkgDef := ir.NewPackageDefinition([]ir.PackageDefinitionModule[ir.Unit, ir.Type[ir.Unit]]{
		ir.PackageDefinitionModuleFromParts[ir.Unit, ir.Type[ir.Unit]](
			moduleName,
			ir.Public(modDef),
		),
	})

	lib := ir.NewLibrary(pkgName, nil, pkgDef)
	decIR := decorationmodels.NewDecorationIR(lib, "test.json")
	entryPoint := "Test:Module:type"

	// Create values with one valid and one invalid
	// Use a properly encoded unit value for the valid one
	opts := jsoncodec.Options{FormatVersion: jsoncodec.FormatV3}
	unitAttr := ir.Unit{}
	unitValue := ir.NewUnitValue[ir.Unit, ir.Unit](unitAttr)
	encodeUnitAttr := func(ir.Unit) (json.RawMessage, error) {
		return json.RawMessage("[]"), nil
	}
	encodeValueUnitAttr := func(ir.Unit) (json.RawMessage, error) {
		return json.RawMessage("[]"), nil
	}
	validJSON, err := jsoncodec.EncodeValue(opts, encodeUnitAttr, encodeValueUnitAttr, unitValue)
	if err != nil {
		t.Fatalf("EncodeValue: %v", err)
	}

	values := decorationmodels.NewDecorationValues(map[string]json.RawMessage{
		"My.Package:Foo:bar": validJSON,
		"My.Package:Foo:baz": json.RawMessage(`{"invalid": "structure"}`),
	})

	result := ValidateDecorationValues(decIR, entryPoint, values)

	if result.Valid {
		t.Error("expected invalid result due to invalid value")
	}
	if result.Checked != 2 {
		t.Errorf("Checked: got %d, want 2", result.Checked)
	}
	if len(result.Errors) != 1 {
		t.Errorf("expected 1 error, got %d: %v", len(result.Errors), result.Errors)
	}
}
