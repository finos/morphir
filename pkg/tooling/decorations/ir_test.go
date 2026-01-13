package decorations

import (
	"encoding/json"
	"os"
	"path/filepath"
	"testing"

	ir "github.com/finos/morphir/pkg/models/ir"
	jsoncodec "github.com/finos/morphir/pkg/models/ir/codec/json"
	decorationmodels "github.com/finos/morphir/pkg/models/ir/decorations"
)

func TestLoadDecorationIR_ValidLibrary(t *testing.T) {
	// Create a temporary IR file
	tmpDir := t.TempDir()
	irPath := filepath.Join(tmpDir, "decoration-ir.json")

	// Create a simple library distribution
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

	// Encode to JSON
	opts := jsoncodec.Options{FormatVersion: jsoncodec.FormatV3}
	data, err := jsoncodec.EncodeDistribution(opts, lib)
	if err != nil {
		t.Fatalf("EncodeDistribution: %v", err)
	}

	// Wrap in distribution format
	wrapped := map[string]interface{}{
		"formatVersion": 3,
		"distribution":  data,
	}

	wrappedJSON, err := json.Marshal(wrapped)
	if err != nil {
		t.Fatalf("Marshal wrapped: %v", err)
	}

	// Write to file
	if err := os.WriteFile(irPath, wrappedJSON, 0644); err != nil {
		t.Fatalf("WriteFile: %v", err)
	}

	// Load the decoration IR
	decIR, err := LoadDecorationIR(irPath)
	if err != nil {
		t.Fatalf("LoadDecorationIR: %v", err)
	}

	// Verify it loaded correctly
	loadedLib, ok := decIR.Distribution().(ir.Library)
	if !ok {
		t.Fatalf("expected Library, got %T", decIR.Distribution())
	}

	if !loadedLib.PackageName().Equal(pkgName) {
		t.Errorf("package name mismatch: got %v, want %v", loadedLib.PackageName(), pkgName)
	}

	if decIR.IRPath() != irPath {
		t.Errorf("IRPath: got %q, want %q", decIR.IRPath(), irPath)
	}
}

func TestLoadDecorationIR_FileNotFound(t *testing.T) {
	_, err := LoadDecorationIR("/nonexistent/path/ir.json")
	if err == nil {
		t.Fatal("expected error for non-existent file")
	}
}

func TestValidateEntryPoint_Valid(t *testing.T) {
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

	// Test valid entry point
	entryPoint := "My.Decoration:Foo:shape"
	if err := ValidateEntryPoint(decIR, entryPoint); err != nil {
		t.Errorf("ValidateEntryPoint: unexpected error: %v", err)
	}
}

func TestValidateEntryPoint_InvalidFormat(t *testing.T) {
	lib := ir.NewLibrary(ir.PathFromString("Test"), nil, ir.EmptyPackageDefinition[ir.Unit, ir.Type[ir.Unit]]())
	decIR := decorationmodels.NewDecorationIR(lib, "test.json")

	// Test invalid format (missing parts)
	entryPoint := "Invalid:Format"
	err := ValidateEntryPoint(decIR, entryPoint)
	if err == nil {
		t.Fatal("expected error for invalid entry point format")
	}
}

func TestValidateEntryPoint_PackageMismatch(t *testing.T) {
	lib := ir.NewLibrary(ir.PathFromString("My.Decoration"), nil, ir.EmptyPackageDefinition[ir.Unit, ir.Type[ir.Unit]]())
	decIR := decorationmodels.NewDecorationIR(lib, "test.json")

	// Test package name mismatch
	entryPoint := "Wrong.Package:Module:Type"
	err := ValidateEntryPoint(decIR, entryPoint)
	if err == nil {
		t.Fatal("expected error for package name mismatch")
	}
}

func TestValidateEntryPoint_ModuleNotFound(t *testing.T) {
	pkgName := ir.PathFromString("My.Decoration")
	modDef := ir.NewModuleDefinition[ir.Unit, ir.Type[ir.Unit]](nil, nil, nil)
	moduleName := ir.PathFromString("ExistingModule")
	pkgDef := ir.NewPackageDefinition([]ir.PackageDefinitionModule[ir.Unit, ir.Type[ir.Unit]]{
		ir.PackageDefinitionModuleFromParts[ir.Unit, ir.Type[ir.Unit]](
			moduleName,
			ir.Public(modDef),
		),
	})

	lib := ir.NewLibrary(pkgName, nil, pkgDef)
	decIR := decorationmodels.NewDecorationIR(lib, "test.json")

	// Test module not found
	entryPoint := "My.Decoration:NonExistentModule:Type"
	err := ValidateEntryPoint(decIR, entryPoint)
	if err == nil {
		t.Fatal("expected error for module not found")
	}
}

func TestValidateEntryPoint_TypeNotFound(t *testing.T) {
	pkgName := ir.PathFromString("My.Decoration")
	modDef := ir.NewModuleDefinition[ir.Unit, ir.Type[ir.Unit]](nil, nil, nil)
	moduleName := ir.PathFromString("Foo")
	pkgDef := ir.NewPackageDefinition([]ir.PackageDefinitionModule[ir.Unit, ir.Type[ir.Unit]]{
		ir.PackageDefinitionModuleFromParts[ir.Unit, ir.Type[ir.Unit]](
			moduleName,
			ir.Public(modDef),
		),
	})

	lib := ir.NewLibrary(pkgName, nil, pkgDef)
	decIR := decorationmodels.NewDecorationIR(lib, "test.json")

	// Test type not found
	entryPoint := "My.Decoration:Foo:NonExistentType"
	err := ValidateEntryPoint(decIR, entryPoint)
	if err == nil {
		t.Fatal("expected error for type not found")
	}
}

func TestExtractDecorationType_Valid(t *testing.T) {
	pkgName := ir.PathFromString("My.Decoration")
	typeName := ir.NameFromParts([]string{"shape"})
	expectedTypeDef := ir.NewTypeAliasDefinition(
		[]ir.Name{},
		ir.NewTypeUnit[ir.Unit](ir.Unit{}),
	)

	modDef := ir.NewModuleDefinition[ir.Unit, ir.Type[ir.Unit]](
		[]ir.ModuleDefinitionType[ir.Unit]{
			ir.ModuleDefinitionTypeFromParts[ir.Unit](
				typeName,
				ir.Public(ir.NewDocumented("Shape type", expectedTypeDef)),
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
	typeDef, err := ExtractDecorationType(decIR, entryPoint)
	if err != nil {
		t.Fatalf("ExtractDecorationType: %v", err)
	}

	// Verify we got the right type
	aliasDef, ok := typeDef.(ir.TypeAliasDefinition[ir.Unit])
	if !ok {
		t.Fatalf("expected TypeAliasDefinition, got %T", typeDef)
	}

	// Check it's the unit type
	exp := aliasDef.Expression()
	_, ok = exp.(ir.TypeUnit[ir.Unit])
	if !ok {
		t.Errorf("expected TypeUnit, got %T", exp)
	}
}

func TestExtractDecorationType_InvalidEntryPoint(t *testing.T) {
	lib := ir.NewLibrary(ir.PathFromString("Test"), nil, ir.EmptyPackageDefinition[ir.Unit, ir.Type[ir.Unit]]())
	decIR := decorationmodels.NewDecorationIR(lib, "test.json")

	entryPoint := "Invalid:Entry:Point"
	_, err := ExtractDecorationType(decIR, entryPoint)
	if err == nil {
		t.Fatal("expected error for invalid entry point")
	}
}
