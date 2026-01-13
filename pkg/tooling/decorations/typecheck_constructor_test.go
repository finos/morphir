package decorations

import (
	"testing"

	ir "github.com/finos/morphir/pkg/models/ir"
	decorationmodels "github.com/finos/morphir/pkg/models/ir/decorations"
)

func TestTypeChecker_ConstructorWithArguments(t *testing.T) {
	// Create a decoration IR with a custom type that has a constructor with arguments
	pkgName := ir.PathFromString("My.Decoration")
	typeName := ir.NameFromParts([]string{"status"})

	// Custom type: type Status = Ok String | Error String
	okConstructor := ir.TypeConstructorFromParts[ir.Unit](
		ir.NameFromParts([]string{"ok"}),
		ir.TypeConstructorArgs[ir.Unit]{
			ir.TypeConstructorArgFromParts[ir.Unit](
				ir.NameFromParts([]string{"message"}),
				ir.NewTypeReference[ir.Unit](ir.Unit{}, ir.FQNameFromParts(
					ir.PathFromString("Morphir.SDK"),
					ir.PathFromString("String"),
					ir.NameFromParts([]string{"string"}),
				), nil),
			),
		},
	)

	customType := ir.NewCustomTypeDefinition[ir.Unit](
		[]ir.Name{},
		ir.Public(ir.TypeConstructors[ir.Unit]{okConstructor}),
	)

	modDef := ir.NewModuleDefinition[ir.Unit, ir.Type[ir.Unit]](
		[]ir.ModuleDefinitionType[ir.Unit]{
			ir.ModuleDefinitionTypeFromParts[ir.Unit](
				typeName,
				ir.Public(ir.NewDocumented("Status type", customType)),
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
	entryPoint := "My.Decoration:Foo:status"

	typeChecker, err := NewTypeChecker(decIR, entryPoint)
	if err != nil {
		t.Fatalf("NewTypeChecker: %v", err)
	}

	// Create a constructor application: Ok "success"
	okCtor := ir.NewConstructorValue[ir.Unit, ir.Unit](
		ir.Unit{},
		ir.FQNameFromParts(
			pkgName,
			moduleName,
			ir.NameFromParts([]string{"ok"}),
		),
	)
	stringArg := ir.NewLiteralValue[ir.Unit, ir.Unit](
		ir.Unit{},
		ir.NewStringLiteral("success"),
	)

	// Apply the constructor to the argument
	applyValue := ir.NewApplyValue[ir.Unit, ir.Unit](ir.Unit{}, okCtor, stringArg)

	// Should pass type checking
	if err := typeChecker.CheckValueType(applyValue); err != nil {
		t.Errorf("CheckValueType: unexpected error: %v", err)
	}
}

func TestTypeChecker_ConstructorWrongArgumentCount(t *testing.T) {
	// Create a decoration IR with a constructor that requires 1 argument
	pkgName := ir.PathFromString("My.Decoration")
	typeName := ir.NameFromParts([]string{"maybe"})

	justConstructor := ir.TypeConstructorFromParts[ir.Unit](
		ir.NameFromParts([]string{"just"}),
		ir.TypeConstructorArgs[ir.Unit]{
			ir.TypeConstructorArgFromParts[ir.Unit](
				ir.NameFromParts([]string{"value"}),
				ir.NewTypeReference[ir.Unit](ir.Unit{}, ir.FQNameFromParts(
					ir.PathFromString("Morphir.SDK"),
					ir.PathFromString("Basics"),
					ir.NameFromParts([]string{"int"}),
				), nil),
			),
		},
	)

	customType := ir.NewCustomTypeDefinition[ir.Unit](
		[]ir.Name{},
		ir.Public(ir.TypeConstructors[ir.Unit]{justConstructor}),
	)

	modDef := ir.NewModuleDefinition[ir.Unit, ir.Type[ir.Unit]](
		[]ir.ModuleDefinitionType[ir.Unit]{
			ir.ModuleDefinitionTypeFromParts[ir.Unit](
				typeName,
				ir.Public(ir.NewDocumented("Maybe type", customType)),
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
	entryPoint := "My.Decoration:Foo:maybe"

	typeChecker, err := NewTypeChecker(decIR, entryPoint)
	if err != nil {
		t.Fatalf("NewTypeChecker: %v", err)
	}

	// Create a constructor without arguments (but it requires 1)
	justCtor := ir.NewConstructorValue[ir.Unit, ir.Unit](
		ir.Unit{},
		ir.FQNameFromParts(
			pkgName,
			moduleName,
			ir.NameFromParts([]string{"just"}),
		),
	)

	// Should fail type checking (wrong argument count)
	if err := typeChecker.CheckValueType(justCtor); err == nil {
		t.Error("expected error for constructor with wrong argument count")
	}
}

func TestTypeChecker_ConstructorWrongArgumentType(t *testing.T) {
	// Create a decoration IR with a constructor that requires a String argument
	pkgName := ir.PathFromString("My.Decoration")
	typeName := ir.NameFromParts([]string{"result"})

	okConstructor := ir.TypeConstructorFromParts[ir.Unit](
		ir.NameFromParts([]string{"ok"}),
		ir.TypeConstructorArgs[ir.Unit]{
			ir.TypeConstructorArgFromParts[ir.Unit](
				ir.NameFromParts([]string{"value"}),
				ir.NewTypeReference[ir.Unit](ir.Unit{}, ir.FQNameFromParts(
					ir.PathFromString("Morphir.SDK"),
					ir.PathFromString("String"),
					ir.NameFromParts([]string{"string"}),
				), nil),
			),
		},
	)

	customType := ir.NewCustomTypeDefinition[ir.Unit](
		[]ir.Name{},
		ir.Public(ir.TypeConstructors[ir.Unit]{okConstructor}),
	)

	modDef := ir.NewModuleDefinition[ir.Unit, ir.Type[ir.Unit]](
		[]ir.ModuleDefinitionType[ir.Unit]{
			ir.ModuleDefinitionTypeFromParts[ir.Unit](
				typeName,
				ir.Public(ir.NewDocumented("Result type", customType)),
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
	entryPoint := "My.Decoration:Foo:result"

	typeChecker, err := NewTypeChecker(decIR, entryPoint)
	if err != nil {
		t.Fatalf("NewTypeChecker: %v", err)
	}

	// Create a constructor application with wrong argument type: Ok 42 (should be String)
	okCtor := ir.NewConstructorValue[ir.Unit, ir.Unit](
		ir.Unit{},
		ir.FQNameFromParts(
			pkgName,
			moduleName,
			ir.NameFromParts([]string{"ok"}),
		),
	)
	intArg := ir.NewLiteralValue[ir.Unit, ir.Unit](
		ir.Unit{},
		ir.NewWholeNumberLiteral(42),
	)

	applyValue := ir.NewApplyValue[ir.Unit, ir.Unit](ir.Unit{}, okCtor, intArg)

	// Should fail type checking (wrong argument type)
	if err := typeChecker.CheckValueType(applyValue); err == nil {
		t.Error("expected error for constructor with wrong argument type")
	}
}

func TestUnwrapConstructorApplication(t *testing.T) {
	// Test unwrapping a simple constructor (no arguments)
	ctorValue := ir.NewConstructorValue[ir.Unit, ir.Unit](
		ir.Unit{},
		ir.FQNameFromParts(
			ir.PathFromString("Test"),
			ir.PathFromString("Module"),
			ir.NameFromParts([]string{"none"}),
		),
	)
	ctor := ctorValue.(ir.ConstructorValue[ir.Unit, ir.Unit])

	unwrappedCtor, args, err := unwrapConstructorApplication(ctorValue)
	if err != nil {
		t.Fatalf("unwrapConstructorApplication: %v", err)
	}

	if !unwrappedCtor.ConstructorName().Equal(ctor.ConstructorName()) {
		t.Errorf("constructor name mismatch")
	}
	if len(args) != 0 {
		t.Errorf("expected 0 arguments, got %d", len(args))
	}
}

func TestUnwrapConstructorApplication_WithArguments(t *testing.T) {
	// Test unwrapping: Apply (Apply (Constructor Just) arg1) arg2
	ctorValue := ir.NewConstructorValue[ir.Unit, ir.Unit](
		ir.Unit{},
		ir.FQNameFromParts(
			ir.PathFromString("Test"),
			ir.PathFromString("Module"),
			ir.NameFromParts([]string{"pair"}),
		),
	)
	ctor := ctorValue.(ir.ConstructorValue[ir.Unit, ir.Unit])
	arg1 := ir.NewLiteralValue[ir.Unit, ir.Unit](ir.Unit{}, ir.NewStringLiteral("first"))
	arg2 := ir.NewLiteralValue[ir.Unit, ir.Unit](ir.Unit{}, ir.NewStringLiteral("second"))

	// Build: Apply (Apply Constructor arg1) arg2
	apply1 := ir.NewApplyValue[ir.Unit, ir.Unit](ir.Unit{}, ctorValue, arg1)
	apply2 := ir.NewApplyValue[ir.Unit, ir.Unit](ir.Unit{}, apply1, arg2)

	unwrappedCtor, args, err := unwrapConstructorApplication(apply2)
	if err != nil {
		t.Fatalf("unwrapConstructorApplication: %v", err)
	}

	if !unwrappedCtor.ConstructorName().Equal(ctor.ConstructorName()) {
		t.Errorf("constructor name mismatch")
	}
	if len(args) != 2 {
		t.Fatalf("expected 2 arguments, got %d", len(args))
	}

	// Verify arguments are in correct order
	if args[0] != arg1 {
		t.Error("first argument mismatch")
	}
	if args[1] != arg2 {
		t.Error("second argument mismatch")
	}
}

func TestUnwrapConstructorApplication_NotConstructor(t *testing.T) {
	// Test with a non-constructor value
	unitValue := ir.NewUnitValue[ir.Unit, ir.Unit](ir.Unit{})

	_, _, err := unwrapConstructorApplication(unitValue)
	if err == nil {
		t.Error("expected error for non-constructor value")
	}
}
