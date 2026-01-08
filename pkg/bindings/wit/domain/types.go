package domain

// Type represents a WIT type.
// This is the top-level interface for all types in the type system.
type Type interface {
	typeMarker()
}

// PrimitiveKind represents the kind of primitive type.
type PrimitiveKind int

const (
	U8 PrimitiveKind = iota
	U16
	U32
	U64
	S8
	S16
	S32
	S64
	F32
	F64
	Bool
	Char
	String
)

// PrimitiveType represents a primitive type (u8, u16, string, bool, etc.).
type PrimitiveType struct {
	Kind PrimitiveKind
}

func (PrimitiveType) typeMarker() {}

// NamedType represents a reference to a named type (record, variant, resource, etc.).
//
// Example: my-record, error-code
type NamedType struct {
	Name Identifier
}

func (NamedType) typeMarker() {}

// ContainerType represents types that contain other types.
// This interface groups all composite types for easier traversal.
type ContainerType interface {
	Type
	containerMarker()
}

// ListType represents a list type.
//
// Example: list<u8>, list<string>
type ListType struct {
	Element Type
}

func (ListType) typeMarker()      {}
func (ListType) containerMarker() {}

// OptionType represents an optional type.
//
// Example: option<string>
type OptionType struct {
	Inner Type
}

func (OptionType) typeMarker()      {}
func (OptionType) containerMarker() {}

// ResultType represents a result type (success or error).
//
// Example: result<string, u32>, result<_, error-code>
type ResultType struct {
	Ok  *Type // nil for result<_, T> or result
	Err *Type // nil for result<T> or result
}

func (ResultType) typeMarker()      {}
func (ResultType) containerMarker() {}

// TupleType represents a tuple type.
//
// Example: tuple<u32, string, bool>
type TupleType struct {
	Types []Type
}

func (TupleType) typeMarker()      {}
func (TupleType) containerMarker() {}

// HandleType represents a resource handle (own or borrow).
//
// Example: borrow<file>, own<descriptor>
type HandleType struct {
	Resource Identifier
	IsBorrow bool // true for borrow<T>, false for own<T>
}

func (HandleType) typeMarker()      {}
func (HandleType) containerMarker() {}

// FutureType represents an async future type (WASI Preview 3).
//
// Example: future<string>, future
type FutureType struct {
	Inner *Type // nil for future with no type
}

func (FutureType) typeMarker()      {}
func (FutureType) containerMarker() {}

// StreamType represents an async stream type (WASI Preview 3).
//
// Example: stream<u8>, stream
type StreamType struct {
	Element *Type // nil for stream with no type
}

func (StreamType) typeMarker()      {}
func (StreamType) containerMarker() {}
