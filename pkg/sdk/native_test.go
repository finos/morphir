package sdk

import (
	"errors"
	"testing"

	ir "github.com/finos/morphir-go/pkg/models/stable/ir"
)

func TestNewNativeFunctionRegistry(t *testing.T) {
	registry := NewNativeFunctionRegistry[ir.Unit, ir.Unit]()
	if registry == nil {
		t.Fatal("Expected non-nil registry")
	}
	if registry.Count() != 0 {
		t.Errorf("Expected empty registry, got %d functions", registry.Count())
	}
}

func TestRegisterAndLookup(t *testing.T) {
	registry := NewNativeFunctionRegistry[ir.Unit, ir.Unit]()

	// Create a test FQName
	fqName := ir.FQNameFromParts(
		ir.PathFromString("Morphir.SDK"),
		ir.PathFromString("Basics"),
		ir.NameFromString("add"),
	)

	// Create a simple native function
	addFunc := func(args []ir.Value[ir.Unit, ir.Unit]) (ir.Value[ir.Unit, ir.Unit], error) {
		if len(args) != 2 {
			return nil, errors.New("add requires 2 arguments")
		}
		// Simplified: just return the first argument for testing
		return args[0], nil
	}

	// Register the function
	registry.Register(fqName, addFunc)

	// Verify registration
	if registry.Count() != 1 {
		t.Errorf("Expected 1 function, got %d", registry.Count())
	}

	// Lookup the function
	retrieved := registry.Lookup(fqName)
	if retrieved == nil {
		t.Fatal("Expected to retrieve registered function")
	}

	// Test the retrieved function
	testArgs := []ir.Value[ir.Unit, ir.Unit]{
		ir.NewLiteralValue[ir.Unit](ir.Unit{}, ir.NewWholeNumberLiteral(42)),
		ir.NewLiteralValue[ir.Unit](ir.Unit{}, ir.NewWholeNumberLiteral(10)),
	}

	result, err := retrieved(testArgs)
	if err != nil {
		t.Fatalf("Function call failed: %v", err)
	}
	if result == nil {
		t.Fatal("Expected non-nil result")
	}
}

func TestHas(t *testing.T) {
	registry := NewNativeFunctionRegistry[ir.Unit, ir.Unit]()

	fqName := ir.FQNameFromParts(
		ir.PathFromString("Morphir.SDK"),
		ir.PathFromString("String"),
		ir.NameFromString("concat"),
	)

	// Should not exist initially
	if registry.Has(fqName) {
		t.Error("Expected function to not exist")
	}

	// Register a dummy function
	registry.Register(fqName, func(args []ir.Value[ir.Unit, ir.Unit]) (ir.Value[ir.Unit, ir.Unit], error) {
		return nil, nil
	})

	// Should exist now
	if !registry.Has(fqName) {
		t.Error("Expected function to exist after registration")
	}
}

func TestLookupNonExistent(t *testing.T) {
	registry := NewNativeFunctionRegistry[ir.Unit, ir.Unit]()

	fqName := ir.FQNameFromParts(
		ir.PathFromString("Morphir.SDK"),
		ir.PathFromString("NonExistent"),
		ir.NameFromString("function"),
	)

	retrieved := registry.Lookup(fqName)
	if retrieved != nil {
		t.Error("Expected nil for non-existent function")
	}
}

func TestMultipleRegistrations(t *testing.T) {
	registry := NewNativeFunctionRegistry[ir.Unit, ir.Unit]()

	// Register multiple functions
	functions := []struct {
		name   ir.FQName
		result string
	}{
		{
			name: ir.FQNameFromParts(
				ir.PathFromString("Morphir.SDK"),
				ir.PathFromString("Basics"),
				ir.NameFromString("add"),
			),
			result: "add",
		},
		{
			name: ir.FQNameFromParts(
				ir.PathFromString("Morphir.SDK"),
				ir.PathFromString("Basics"),
				ir.NameFromString("subtract"),
			),
			result: "subtract",
		},
		{
			name: ir.FQNameFromParts(
				ir.PathFromString("Morphir.SDK"),
				ir.PathFromString("String"),
				ir.NameFromString("concat"),
			),
			result: "concat",
		},
	}

	for _, fn := range functions {
		expectedResult := fn.result
		registry.Register(fn.name, func(args []ir.Value[ir.Unit, ir.Unit]) (ir.Value[ir.Unit, ir.Unit], error) {
			return ir.NewLiteralValue[ir.Unit](ir.Unit{}, ir.NewStringLiteral(expectedResult)), nil
		})
	}

	if registry.Count() != len(functions) {
		t.Errorf("Expected %d functions, got %d", len(functions), registry.Count())
	}

	// Verify each function can be retrieved
	for _, fn := range functions {
		if !registry.Has(fn.name) {
			t.Errorf("Function %v should be registered", fn.name)
		}
	}
}

func TestFQNameToString(t *testing.T) {
	tests := []struct {
		name     string
		fqName   ir.FQName
		expected string
	}{
		{
			name: "Simple function name",
			fqName: ir.FQNameFromParts(
				ir.PathFromString("Morphir.SDK"),
				ir.PathFromString("Basics"),
				ir.NameFromString("add"),
			),
			expected: "Morphir.SDK:Basics:Add",
		},
		{
			name: "Multi-part module path",
			fqName: ir.FQNameFromParts(
				ir.PathFromString("Morphir.SDK"),
				ir.PathFromString("String.Advanced"),
				ir.NameFromString("trim"),
			),
			expected: "Morphir.SDK:String.Advanced:Trim",
		},
		{
			name: "Different package",
			fqName: ir.FQNameFromParts(
				ir.PathFromString("My.Package"),
				ir.PathFromString("Module"),
				ir.NameFromString("function"),
			),
			expected: "My.Package:Module:Function",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := fqNameToString(tt.fqName)
			if result != tt.expected {
				t.Errorf("Expected %q, got %q", tt.expected, result)
			}
		})
	}
}

func TestRegistryWithDifferentTypeParameters(t *testing.T) {
	// Test with custom type parameters
	type CustomTA struct {
		TypeInfo string
	}
	type CustomVA struct {
		SourceLocation int
	}

	registry := NewNativeFunctionRegistry[CustomTA, CustomVA]()

	fqName := ir.FQNameFromParts(
		ir.PathFromString("Morphir.SDK"),
		ir.PathFromString("Test"),
		ir.NameFromString("custom"),
	)

	customFunc := func(args []ir.Value[CustomTA, CustomVA]) (ir.Value[CustomTA, CustomVA], error) {
		return ir.NewLiteralValue[CustomTA](CustomVA{SourceLocation: 100}, ir.NewWholeNumberLiteral(42)), nil
	}

	registry.Register(fqName, customFunc)

	retrieved := registry.Lookup(fqName)
	if retrieved == nil {
		t.Fatal("Expected to retrieve custom function")
	}

	result, err := retrieved(nil)
	if err != nil {
		t.Fatalf("Function call failed: %v", err)
	}

	// Verify attributes
	attrs := result.Attributes()
	if attrs.SourceLocation != 100 {
		t.Errorf("Expected SourceLocation 100, got %d", attrs.SourceLocation)
	}
}

func TestOverwriteRegistration(t *testing.T) {
	registry := NewNativeFunctionRegistry[ir.Unit, ir.Unit]()

	fqName := ir.FQNameFromParts(
		ir.PathFromString("Morphir.SDK"),
		ir.PathFromString("Test"),
		ir.NameFromString("func"),
	)

	// Register first implementation
	firstFunc := func(args []ir.Value[ir.Unit, ir.Unit]) (ir.Value[ir.Unit, ir.Unit], error) {
		return ir.NewLiteralValue[ir.Unit](ir.Unit{}, ir.NewWholeNumberLiteral(1)), nil
	}
	registry.Register(fqName, firstFunc)

	// Register second implementation (overwrite)
	secondFunc := func(args []ir.Value[ir.Unit, ir.Unit]) (ir.Value[ir.Unit, ir.Unit], error) {
		return ir.NewLiteralValue[ir.Unit](ir.Unit{}, ir.NewWholeNumberLiteral(2)), nil
	}
	registry.Register(fqName, secondFunc)

	// Should still have only 1 function
	if registry.Count() != 1 {
		t.Errorf("Expected 1 function after overwrite, got %d", registry.Count())
	}

	// Verify the second implementation is used
	retrieved := registry.Lookup(fqName)
	result, err := retrieved(nil)
	if err != nil {
		t.Fatalf("Function call failed: %v", err)
	}

	litVal, ok := result.(ir.LiteralValue[ir.Unit, ir.Unit])
	if !ok {
		t.Fatal("Expected LiteralValue")
	}

	wholeNumLit, ok := litVal.Literal().(ir.WholeNumberLiteral)
	if !ok {
		t.Fatal("Expected WholeNumberLiteral")
	}

	if wholeNumLit.Value() != 2 {
		t.Errorf("Expected value 2, got %d", wholeNumLit.Value())
	}
}
