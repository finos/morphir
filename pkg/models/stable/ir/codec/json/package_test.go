package json

import (
	"testing"

	ir "github.com/finos/morphir-go/pkg/models/stable/ir"
)

func TestPackageSpecificationRoundTripV3(t *testing.T) {
	opts := Options{FormatVersion: FormatV3}

	// Create a module specification
	typeName := ir.NameFromParts([]string{"my", "type"})
	typeSpec := ir.NewTypeAliasSpecification(
		[]ir.Name{ir.NameFromParts([]string{"a"})},
		ir.NewTypeUnit[unitAttr](unitAttr{}),
	)

	modSpec := ir.NewModuleSpecification(
		[]ir.ModuleSpecificationType[unitAttr]{
			ir.ModuleSpecificationTypeFromParts[unitAttr](
				typeName,
				ir.NewDocumented("Type doc", typeSpec),
			),
		},
		nil,
		nil,
	)

	moduleName := ir.PathFromString("MyModule")

	pkgSpec := ir.NewPackageSpecification([]ir.PackageSpecificationModule[unitAttr]{
		ir.PackageSpecificationModuleFromParts(moduleName, modSpec),
	})

	data, err := EncodePackageSpecification(opts, encodeUnitAttr, pkgSpec)
	if err != nil {
		t.Fatalf("EncodePackageSpecification: %v", err)
	}

	decoded, err := DecodePackageSpecification(opts, decodeUnitAttr, data)
	if err != nil {
		t.Fatalf("DecodePackageSpecification: %v", err)
	}

	// Verify modules
	modules := decoded.Modules()
	if len(modules) != 1 {
		t.Fatalf("expected 1 module, got %d", len(modules))
	}
	if !modules[0].Name().Equal(moduleName) {
		t.Fatalf("module name mismatch")
	}
	if len(modules[0].Spec().Types()) != 1 {
		t.Fatalf("expected 1 type in module, got %d", len(modules[0].Spec().Types()))
	}
}

func TestPackageDefinitionRoundTripV3(t *testing.T) {
	opts := Options{FormatVersion: FormatV3}

	// Create a module definition
	typeName := ir.NameFromParts([]string{"my", "type"})
	typeDef := ir.NewTypeAliasDefinition(
		[]ir.Name{ir.NameFromParts([]string{"a"})},
		ir.NewTypeUnit[unitAttr](unitAttr{}),
	)

	modDef := ir.NewModuleDefinition[unitAttr, unitAttr](
		[]ir.ModuleDefinitionType[unitAttr]{
			ir.ModuleDefinitionTypeFromParts[unitAttr](
				typeName,
				ir.Public(ir.NewDocumented("Type doc", typeDef)),
			),
		},
		nil,
		nil,
	)

	moduleName := ir.PathFromString("MyModule")

	pkgDef := ir.NewPackageDefinition([]ir.PackageDefinitionModule[unitAttr, unitAttr]{
		ir.PackageDefinitionModuleFromParts[unitAttr, unitAttr](
			moduleName,
			ir.Public(modDef),
		),
	})

	data, err := EncodePackageDefinition(opts, encodeUnitAttr, encodeValueUnitAttr, pkgDef)
	if err != nil {
		t.Fatalf("EncodePackageDefinition: %v", err)
	}

	decoded, err := DecodePackageDefinition(opts, decodeUnitAttr, decodeValueUnitAttr, data)
	if err != nil {
		t.Fatalf("DecodePackageDefinition: %v", err)
	}

	// Verify modules
	modules := decoded.Modules()
	if len(modules) != 1 {
		t.Fatalf("expected 1 module, got %d", len(modules))
	}
	if !modules[0].Name().Equal(moduleName) {
		t.Fatalf("module name mismatch")
	}
	if modules[0].Definition().Access() != ir.AccessPublic {
		t.Fatalf("module access mismatch: expected Public")
	}
	if len(modules[0].Definition().Value().Types()) != 1 {
		t.Fatalf("expected 1 type in module, got %d", len(modules[0].Definition().Value().Types()))
	}
}

func TestEmptyPackageSpecificationRoundTrip(t *testing.T) {
	opts := Options{FormatVersion: FormatV3}

	pkgSpec := ir.EmptyPackageSpecification[unitAttr]()

	data, err := EncodePackageSpecification(opts, encodeUnitAttr, pkgSpec)
	if err != nil {
		t.Fatalf("EncodePackageSpecification: %v", err)
	}

	decoded, err := DecodePackageSpecification(opts, decodeUnitAttr, data)
	if err != nil {
		t.Fatalf("DecodePackageSpecification: %v", err)
	}

	if len(decoded.Modules()) != 0 {
		t.Fatalf("expected 0 modules, got %d", len(decoded.Modules()))
	}
}

func TestPackageSpecificationMultipleModules(t *testing.T) {
	opts := Options{FormatVersion: FormatV3}

	mod1Name := ir.PathFromString("Module.One")
	mod2Name := ir.PathFromString("Module.Two")

	modSpec1 := ir.NewModuleSpecification[unitAttr](nil, nil, nil)
	modSpec2 := ir.NewModuleSpecification[unitAttr](nil, nil, nil)

	pkgSpec := ir.NewPackageSpecification([]ir.PackageSpecificationModule[unitAttr]{
		ir.PackageSpecificationModuleFromParts(mod1Name, modSpec1),
		ir.PackageSpecificationModuleFromParts(mod2Name, modSpec2),
	})

	data, err := EncodePackageSpecification(opts, encodeUnitAttr, pkgSpec)
	if err != nil {
		t.Fatalf("EncodePackageSpecification: %v", err)
	}

	decoded, err := DecodePackageSpecification(opts, decodeUnitAttr, data)
	if err != nil {
		t.Fatalf("DecodePackageSpecification: %v", err)
	}

	modules := decoded.Modules()
	if len(modules) != 2 {
		t.Fatalf("expected 2 modules, got %d", len(modules))
	}
}

func TestLookupModuleSpecification(t *testing.T) {
	moduleName := ir.PathFromString("MyModule")
	modSpec := ir.NewModuleSpecification[unitAttr](nil, nil, nil)

	pkgSpec := ir.NewPackageSpecification([]ir.PackageSpecificationModule[unitAttr]{
		ir.PackageSpecificationModuleFromParts(moduleName, modSpec),
	})

	// Test found
	found := ir.LookupModuleSpecification(moduleName, pkgSpec)
	if found == nil {
		t.Fatalf("expected to find module specification")
	}

	// Test not found
	notFound := ir.LookupModuleSpecification(ir.PathFromString("Other"), pkgSpec)
	if notFound != nil {
		t.Fatalf("expected not to find module specification")
	}
}
