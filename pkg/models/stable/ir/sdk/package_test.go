package sdk

import (
	"testing"

	ir "github.com/finos/morphir-go/pkg/models/stable/ir"
)

func TestPackageName(t *testing.T) {
	pkgName := PackageName()
	expected := ir.PathFromString("Morphir.SDK")
	if !pkgName.Equal(expected) {
		t.Errorf("Expected package name %v, got %v", expected, pkgName)
	}
}

func TestPackageSpec(t *testing.T) {
	spec := PackageSpec()

	// Get all modules
	modules := spec.Modules()

	// We should have 21 modules
	expectedModuleCount := 21
	if len(modules) != expectedModuleCount {
		t.Errorf("Expected %d modules, got %d", expectedModuleCount, len(modules))
	}

	// Verify all expected modules are present
	expectedModules := []string{
		// Core types
		"Basics", "List", "Maybe", "Result",
		// String and character
		"String", "Char",
		// Numeric
		"Int", "Decimal", "Number",
		// Collections
		"Tuple", "Dict", "Set",
		// Date and time
		"LocalDate", "LocalTime",
		// Advanced patterns
		"ResultList", "Aggregate", "Rule", "StatefulApp",
		// Specialized types
		"UUID", "Key", "Regex",
	}

	moduleMap := make(map[string]bool)
	for _, module := range modules {
		moduleMap[module.Name().ToString(func(n ir.Name) string { return n.ToTitleCase() }, ".")] = true
	}

	for _, expectedName := range expectedModules {
		if !moduleMap[expectedName] {
			t.Errorf("Expected module %s not found in package", expectedName)
		}
	}
}

func TestPackageSpecModulesAreValid(t *testing.T) {
	spec := PackageSpec()
	modules := spec.Modules()

	// Verify each module has a non-empty specification
	for _, module := range modules {
		moduleSpec := module.Spec()

		// Each module should have at least types or values
		types := moduleSpec.Types()
		values := moduleSpec.Values()

		if len(types) == 0 && len(values) == 0 {
			t.Errorf("Module %s has no types or values", module.Name().ToString(func(n ir.Name) string { return n.ToTitleCase() }, "."))
		}
	}
}

func TestPackageSpecBasicsModule(t *testing.T) {
	spec := PackageSpec()
	modules := spec.Modules()

	// Find the Basics module
	var basicsSpec ir.ModuleSpecification[ir.Unit]
	found := false
	for _, module := range modules {
		if module.Name().ToString(func(n ir.Name) string { return n.ToTitleCase() }, ".") == "Basics" {
			basicsSpec = module.Spec()
			found = true
			break
		}
	}

	if !found {
		t.Fatal("Basics module not found in package")
	}

	// Verify it has the expected types
	types := basicsSpec.Types()
	if len(types) != 5 {
		t.Errorf("Expected Basics to have 5 types, got %d", len(types))
	}

	// Verify it has values
	values := basicsSpec.Values()
	if len(values) != 47 {
		t.Errorf("Expected Basics to have 47 functions, got %d", len(values))
	}
}

func TestPackageSpecListModule(t *testing.T) {
	spec := PackageSpec()
	modules := spec.Modules()

	// Find the List module
	var listSpec ir.ModuleSpecification[ir.Unit]
	found := false
	for _, module := range modules {
		if module.Name().ToString(func(n ir.Name) string { return n.ToTitleCase() }, ".") == "List" {
			listSpec = module.Spec()
			found = true
			break
		}
	}

	if !found {
		t.Fatal("List module not found in package")
	}

	// Verify it has the List type
	types := listSpec.Types()
	if len(types) != 1 {
		t.Errorf("Expected List to have 1 type, got %d", len(types))
	}

	// Verify the type is named "List"
	if types[0].Name().ToCamelCase() != "list" {
		t.Errorf("Expected type 'list', got %s", types[0].Name().ToCamelCase())
	}
}

func TestPackageSpecDecimalModule(t *testing.T) {
	spec := PackageSpec()
	modules := spec.Modules()

	// Find the Decimal module
	var decimalSpec ir.ModuleSpecification[ir.Unit]
	found := false
	for _, module := range modules {
		if module.Name().ToString(func(n ir.Name) string { return n.ToTitleCase() }, ".") == "Decimal" {
			decimalSpec = module.Spec()
			found = true
			break
		}
	}

	if !found {
		t.Fatal("Decimal module not found in package")
	}

	// Verify it has the Decimal type
	types := decimalSpec.Types()
	if len(types) != 1 {
		t.Errorf("Expected Decimal to have 1 type, got %d", len(types))
	}

	// Verify it has many functions
	values := decimalSpec.Values()
	if len(values) != 34 {
		t.Errorf("Expected Decimal to have 34 functions, got %d", len(values))
	}
}
