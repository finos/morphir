package domain

// Interface represents a named collection of types and functions.
// Interfaces are reusable units that can be imported and exported.
//
// Example WIT:
//
//	interface wall-clock {
//	    record datetime {
//	        seconds: u64,
//	        nanoseconds: u32,
//	    }
//	    now: func() -> datetime;
//	}
type Interface struct {
	Name      Identifier
	Types     []TypeDef
	Functions []Function
	Uses      []Use
	Docs      Documentation
}

// TypeDef represents a type definition (record, variant, enum, flags, resource, or type alias).
//
// Example WIT:
//
//	record point { x: s32, y: s32 }
//	variant result { ok(string), err(u32) }
//	enum color { red, green, blue }
type TypeDef struct {
	Name Identifier
	Kind TypeDefKind
	Docs Documentation
}

// TypeDefKind represents the kind of type definition.
// This is a discriminated union of all possible type definition kinds.
type TypeDefKind interface {
	typeDefKindMarker()
}

// RecordDef defines a record type (struct-like with named fields).
//
// Example: record point { x: s32, y: s32 }
type RecordDef struct {
	Fields []Field
}

func (RecordDef) typeDefKindMarker() {}

// VariantDef defines a variant type (tagged union with optional payloads).
//
// Example: variant result { ok(string), err(u32) }
type VariantDef struct {
	Cases []VariantCase
}

func (VariantDef) typeDefKindMarker() {}

// EnumDef defines an enum type (variant without payloads).
//
// Example: enum color { red, green, blue }
type EnumDef struct {
	Cases []Identifier
}

func (EnumDef) typeDefKindMarker() {}

// FlagsDef defines a flags type (bitfield of boolean flags).
//
// Example: flags permissions { read, write, execute }
type FlagsDef struct {
	Flags []Identifier
}

func (FlagsDef) typeDefKindMarker() {}

// ResourceDef defines a resource type (handle-based type with methods).
//
// Example:
//
//	resource file {
//	    read: func() -> string;
//	    write: func(data: string);
//	}
type ResourceDef struct {
	Constructor *Constructor
	Methods     []ResourceMethod
}

func (ResourceDef) typeDefKindMarker() {}

// TypeAliasDef defines a type alias.
//
// Example: type my-size = u32;
type TypeAliasDef struct {
	Target Type
}

func (TypeAliasDef) typeDefKindMarker() {}

// Field represents a named field in a record.
type Field struct {
	Name Identifier
	Type Type
	Docs Documentation
}

// VariantCase represents a case in a variant type.
type VariantCase struct {
	Name    Identifier
	Payload *Type // nil if no payload
	Docs    Documentation
}

// ResourceMethod represents a method on a resource.
type ResourceMethod struct {
	Name     Identifier
	Function Function
	IsStatic bool
}

// Constructor represents a resource constructor.
type Constructor struct {
	Params []Param
}

// Function represents a function definition.
//
// Example: add: func(a: u32, b: u32) -> u32;
type Function struct {
	Name    Identifier
	Params  []Param
	Results []Type // empty for no return, 1+ for returns
	IsAsync bool
	Docs    Documentation
}

// Param represents a function parameter.
type Param struct {
	Name Identifier
	Type Type
}
