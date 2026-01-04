package json

import (
	"encoding/json"
	"testing"

	ir "github.com/finos/morphir/pkg/models/ir"
)

func TestLibraryRoundTripV3(t *testing.T) {
	opts := Options{FormatVersion: FormatV3}

	pkgName := ir.PathFromString("My.Package")

	// Create a simple module definition
	typeName := ir.NameFromParts([]string{"my", "type"})
	typeDef := ir.NewTypeAliasDefinition(
		[]ir.Name{},
		ir.NewTypeUnit[ir.Unit](ir.Unit{}),
	)

	modDef := ir.NewModuleDefinition[ir.Unit, ir.Type[ir.Unit]](
		[]ir.ModuleDefinitionType[ir.Unit]{
			ir.ModuleDefinitionTypeFromParts[ir.Unit](
				typeName,
				ir.Public(ir.NewDocumented("Type doc", typeDef)),
			),
		},
		nil,
		nil,
	)

	moduleName := ir.PathFromString("MyModule")

	pkgDef := ir.NewPackageDefinition([]ir.PackageDefinitionModule[ir.Unit, ir.Type[ir.Unit]]{
		ir.PackageDefinitionModuleFromParts[ir.Unit, ir.Type[ir.Unit]](
			moduleName,
			ir.Public(modDef),
		),
	})

	lib := ir.NewLibrary(pkgName, nil, pkgDef)

	data, err := EncodeDistribution(opts, lib)
	if err != nil {
		t.Fatalf("EncodeDistribution: %v", err)
	}

	decoded, err := DecodeDistribution(opts, data)
	if err != nil {
		t.Fatalf("DecodeDistribution: %v", err)
	}

	decodedLib, ok := decoded.(ir.Library)
	if !ok {
		t.Fatalf("expected Library, got %T", decoded)
	}

	if !decodedLib.PackageName().Equal(pkgName) {
		t.Fatalf("package name mismatch")
	}

	if len(decodedLib.Dependencies()) != 0 {
		t.Fatalf("expected 0 dependencies, got %d", len(decodedLib.Dependencies()))
	}

	modules := decodedLib.Definition().Modules()
	if len(modules) != 1 {
		t.Fatalf("expected 1 module, got %d", len(modules))
	}
}

func TestLibraryWithDependenciesRoundTripV3(t *testing.T) {
	opts := Options{FormatVersion: FormatV3}

	pkgName := ir.PathFromString("My.Package")
	depName := ir.PathFromString("Dep.Package")

	// Create a dependency specification
	depSpec := ir.EmptyPackageSpecification[ir.Unit]()

	// Create empty package definition
	pkgDef := ir.EmptyPackageDefinition[ir.Unit, ir.Type[ir.Unit]]()

	lib := ir.NewLibrary(
		pkgName,
		[]ir.LibraryDependency{
			ir.LibraryDependencyFromParts(depName, depSpec),
		},
		pkgDef,
	)

	data, err := EncodeDistribution(opts, lib)
	if err != nil {
		t.Fatalf("EncodeDistribution: %v", err)
	}

	decoded, err := DecodeDistribution(opts, data)
	if err != nil {
		t.Fatalf("DecodeDistribution: %v", err)
	}

	decodedLib, ok := decoded.(ir.Library)
	if !ok {
		t.Fatalf("expected Library, got %T", decoded)
	}

	deps := decodedLib.Dependencies()
	if len(deps) != 1 {
		t.Fatalf("expected 1 dependency, got %d", len(deps))
	}

	if !deps[0].Name().Equal(depName) {
		t.Fatalf("dependency name mismatch")
	}
}

func TestLibraryJSONStructure(t *testing.T) {
	opts := Options{FormatVersion: FormatV3}

	pkgName := ir.PathFromString("My.Package")
	pkgDef := ir.EmptyPackageDefinition[ir.Unit, ir.Type[ir.Unit]]()

	lib := ir.NewLibrary(pkgName, nil, pkgDef)

	data, err := EncodeDistribution(opts, lib)
	if err != nil {
		t.Fatalf("EncodeDistribution: %v", err)
	}

	// Verify it's a tuple starting with "Library"
	var tuple []json.RawMessage
	if err := json.Unmarshal(data, &tuple); err != nil {
		t.Fatalf("unmarshal tuple: %v", err)
	}

	if len(tuple) != 4 {
		t.Fatalf("expected 4 elements, got %d", len(tuple))
	}

	var tag string
	if err := json.Unmarshal(tuple[0], &tag); err != nil {
		t.Fatalf("unmarshal tag: %v", err)
	}

	if tag != "Library" {
		t.Fatalf("expected tag 'Library', got %q", tag)
	}
}

func TestLookupPackageSpecification(t *testing.T) {
	pkgName := ir.PathFromString("My.Package")
	depName := ir.PathFromString("Dep.Package")
	depSpec := ir.EmptyPackageSpecification[ir.Unit]()
	pkgDef := ir.EmptyPackageDefinition[ir.Unit, ir.Type[ir.Unit]]()

	lib := ir.NewLibrary(
		pkgName,
		[]ir.LibraryDependency{
			ir.LibraryDependencyFromParts(depName, depSpec),
		},
		pkgDef,
	)

	// Test found
	found := ir.LookupPackageSpecification(depName, lib)
	if found == nil {
		t.Fatalf("expected to find package specification")
	}

	// Test not found
	notFound := ir.LookupPackageSpecification(ir.PathFromString("Other"), lib)
	if notFound != nil {
		t.Fatalf("expected not to find package specification")
	}
}
