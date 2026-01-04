package sdk

import (
	ir "github.com/finos/morphir/pkg/models/ir"
)

// NativeFunction represents a native implementation of a Morphir SDK function.
// It takes a list of argument values and returns a result value or an error.
//
// The type parameters TA and VA represent type attributes and value attributes
// respectively, matching the Morphir IR Value representation.
type NativeFunction[TA any, VA any] func(args []ir.Value[TA, VA]) (ir.Value[TA, VA], error)

// NativeFunctionRegistry maps fully qualified names to their native implementations.
// This registry connects IR function references to their runtime Go implementations.
type NativeFunctionRegistry[TA any, VA any] struct {
	functions map[string]NativeFunction[TA, VA]
}

// NewNativeFunctionRegistry creates a new empty registry.
func NewNativeFunctionRegistry[TA any, VA any]() *NativeFunctionRegistry[TA, VA] {
	return &NativeFunctionRegistry[TA, VA]{
		functions: make(map[string]NativeFunction[TA, VA]),
	}
}

// Register adds a native function implementation to the registry.
// The name should be a fully qualified name (package.module.function).
func (r *NativeFunctionRegistry[TA, VA]) Register(name ir.FQName, fn NativeFunction[TA, VA]) {
	key := fqNameToString(name)
	r.functions[key] = fn
}

// Lookup retrieves a native function by its fully qualified name.
// Returns nil if the function is not registered.
func (r *NativeFunctionRegistry[TA, VA]) Lookup(name ir.FQName) NativeFunction[TA, VA] {
	key := fqNameToString(name)
	return r.functions[key]
}

// Has checks if a native function is registered for the given name.
func (r *NativeFunctionRegistry[TA, VA]) Has(name ir.FQName) bool {
	key := fqNameToString(name)
	_, exists := r.functions[key]
	return exists
}

// Count returns the number of registered native functions.
func (r *NativeFunctionRegistry[TA, VA]) Count() int {
	return len(r.functions)
}

// fqNameToString converts an FQName to a string key for the registry.
// Format: "package.path:module.path:local.name"
func fqNameToString(name ir.FQName) string {
	packagePath := name.PackagePath().ToString(func(n ir.Name) string { return n.ToTitleCase() }, ".")
	modulePath := name.ModulePath().ToString(func(n ir.Name) string { return n.ToTitleCase() }, ".")
	localName := name.LocalName().ToTitleCase()

	return packagePath + ":" + modulePath + ":" + localName
}

// StringToFQName parses a string key back to an FQName.
// This is primarily for testing and debugging purposes.
func StringToFQName(key string) (ir.FQName, bool) {
	// Parse the key format "package.path:module.path:local.name"
	// This is a simplified implementation for now
	// TODO: Implement full parser if needed for advanced use cases
	return ir.FQName{}, false
}
