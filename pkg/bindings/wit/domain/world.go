package domain

// World represents a complete component boundary with imports and exports.
// Worlds describe what a WebAssembly component requires and provides.
//
// Example WIT:
//
//	world my-app {
//	    import wasi:clocks/wall-clock;
//	    import logger: interface {
//	        log: func(msg: string);
//	    }
//	    export run: func();
//	}
type World struct {
	Name    Identifier
	Imports []WorldItem
	Exports []WorldItem
	Uses    []Use
	Docs    Documentation
}

// WorldItem represents an import or export in a world.
// This is a discriminated union - either an interface reference or a function.
type WorldItem interface {
	worldItemMarker()
	ItemName() Identifier
}

// InterfaceItem represents an interface import/export in a world.
//
// Example: import wasi:clocks/wall-clock;
// Example: import logger: interface { ... }
type InterfaceItem struct {
	Name Identifier
	Ref  InterfaceRef
}

func (i InterfaceItem) worldItemMarker()     {}
func (i InterfaceItem) ItemName() Identifier { return i.Name }

// FunctionItem represents a function import/export in a world.
//
// Example: export run: func();
// Example: import get-time: func() -> u64;
type FunctionItem struct {
	Func Function
}

func (f FunctionItem) worldItemMarker()     {}
func (f FunctionItem) ItemName() Identifier { return f.Func.Name }

// InterfaceRef represents a reference to an interface.
// This is a discriminated union - either inline or external reference.
type InterfaceRef interface {
	interfaceRefMarker()
}

// InlineInterface is an interface defined directly in the world.
//
// Example:
//
//	import logger: interface {
//	    log: func(msg: string);
//	}
type InlineInterface struct {
	Interface Interface
}

func (InlineInterface) interfaceRefMarker() {}

// ExternalInterfaceRef references an interface from a use path.
//
// Example: import wasi:clocks/wall-clock;
type ExternalInterfaceRef struct {
	Path UsePath
}

func (ExternalInterfaceRef) interfaceRefMarker() {}
