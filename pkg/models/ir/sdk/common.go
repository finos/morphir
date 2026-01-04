package sdk

import (
	ir "github.com/finos/morphir/pkg/models/ir"
)

// sdkPackageName is the package name for the Morphir SDK.
var sdkPackageName = ir.PathFromString("Morphir.SDK")

// ToFQName creates a fully qualified name in the Morphir.SDK package.
// It takes a module path and a local name and returns an FQName.
func ToFQName(modulePath ir.ModuleName, localName string) ir.FQName {
	return ir.FQNameFromParts(sdkPackageName, modulePath, ir.NameFromString(localName))
}

// TVar creates a type variable with Unit attributes.
func TVar(name string) ir.Type[ir.Unit] {
	return ir.NewTypeVariable(ir.Unit{}, ir.NameFromString(name))
}

// TFun creates a curried function type from a list of parameter types and a return type.
// For example, TFun([]Type{Int, String}, Bool) creates: Int -> String -> Bool
func TFun(params []ir.Type[ir.Unit], returnType ir.Type[ir.Unit]) ir.Type[ir.Unit] {
	if len(params) == 0 {
		return returnType
	}
	// Build the function type from right to left (currying)
	result := returnType
	for i := len(params) - 1; i >= 0; i-- {
		result = ir.NewTypeFunction(ir.Unit{}, params[i], result)
	}
	return result
}

// VSpecInput represents a single input parameter for a value specification.
type VSpecInput struct {
	Name string
	Type ir.Type[ir.Unit]
}

// VSpec creates a documented value specification.
// It takes a function name, a list of inputs, and an output type.
func VSpec(name string, inputs []VSpecInput, output ir.Type[ir.Unit], doc string) ir.ModuleSpecificationValue[ir.Unit] {
	// Convert inputs to value specification inputs
	specInputs := make([]ir.ValueSpecificationInput[ir.Unit], len(inputs))
	for i, input := range inputs {
		specInputs[i] = ir.ValueSpecificationInputFromParts(
			ir.NameFromString(input.Name),
			input.Type,
		)
	}

	spec := ir.NewValueSpecification(specInputs, output)
	documented := ir.NewDocumented(doc, spec)

	return ir.ModuleSpecificationValueFromParts(
		ir.NameFromString(name),
		documented,
	)
}

// BinaryApply creates a binary function application.
// It represents: fn arg1 arg2
func BinaryApply(attributes ir.Unit, fn ir.Value[ir.Unit, ir.Unit], arg1 ir.Value[ir.Unit, ir.Unit], arg2 ir.Value[ir.Unit, ir.Unit]) ir.Value[ir.Unit, ir.Unit] {
	// Apply fn to arg1
	firstApp := ir.NewApplyValue[ir.Unit, ir.Unit](attributes, fn, arg1)
	// Apply the result to arg2
	return ir.NewApplyValue[ir.Unit, ir.Unit](attributes, firstApp, arg2)
}

// OrderType creates an Order type reference (from Basics module)
func OrderType() ir.Type[ir.Unit] {
	return ir.NewTypeReference(
		ir.Unit{},
		ToFQName(BasicsModuleName(), "Order"),
		nil,
	)
}
