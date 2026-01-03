package sdk

import (
	ir "github.com/finos/morphir-go/pkg/models/stable/ir"
)

// KeyModuleName returns the module name for Morphir.SDK.Key
func KeyModuleName() ir.ModuleName {
	return ir.PathFromString("Key")
}

// KeyModuleSpec returns the module specification for Morphir.SDK.Key
func KeyModuleSpec() ir.ModuleSpecification[ir.Unit] {
	return ir.NewModuleSpecification(
		nil, // No types defined (using type aliases)
		keyValues(),
		nil,
	)
}

// keyValues returns the value specifications for the Key module
func keyValues() []ir.ModuleSpecificationValue[ir.Unit] {
	values := []ir.ModuleSpecificationValue[ir.Unit]{
		// Key0 - no key (sentinel)
		VSpec("noKey", []VSpecInput{},
			intType(),
			"A sentinel value representing no key."),

		VSpec("key0", []VSpecInput{
			{Name: "value", Type: intType()},
		}, intType(),
			"Create a Key0 from an integer."),
	}

	// Generate key2 through key16 functions
	for n := 2; n <= 16; n++ {
		inputs := make([]VSpecInput, n+1) // n getter functions + 1 source value

		// Create getter function inputs
		for i := 0; i < n; i++ {
			getterNum := i + 1
			getterName := "getKey"
			if getterNum < 10 {
				getterName += string(rune('0' + getterNum))
			} else {
				getterName += string(rune('0'+getterNum/10)) + string(rune('0'+getterNum%10))
			}
			inputs[i] = VSpecInput{
				Name: getterName,
				Type: TFun([]ir.Type[ir.Unit]{TVar("a")}, TVar(string(rune('k'+byte(i))))),
			}
		}

		// Add source value parameter
		inputs[n] = VSpecInput{
			Name: "value",
			Type: TVar("a"),
		}

		// Build the return type parameters
		keyTypeParams := make([]ir.Type[ir.Unit], n)
		for i := 0; i < n; i++ {
			keyTypeParams[i] = TVar(string(rune('k' + byte(i))))
		}

		// Create the KeyN type reference
		keyTypeName := "Key"
		keyFuncName := "key"
		keyDesc := "Create a composite key with "
		if n < 10 {
			keyTypeName += string(rune('0' + n))
			keyFuncName += string(rune('0' + n))
			keyDesc += string(rune('0' + n))
		} else {
			keyTypeName += string(rune('0'+n/10)) + string(rune('0'+n%10))
			keyFuncName += string(rune('0'+n/10)) + string(rune('0'+n%10))
			keyDesc += string(rune('0'+n/10)) + string(rune('0'+n%10))
		}
		keyDesc += " fields."

		keyNType := ir.NewTypeReference(
			ir.Unit{},
			ToFQName(KeyModuleName(), keyTypeName),
			keyTypeParams,
		)

		values = append(values, VSpec(
			keyFuncName,
			inputs,
			keyNType,
			keyDesc,
		))
	}

	return values
}
