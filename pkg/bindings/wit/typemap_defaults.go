package wit

import (
	"github.com/finos/morphir/pkg/bindings/typemap"
)

// BindingName is the canonical name for the WIT binding.
const BindingName = "wit"

// WITDefaults implements typemap.DefaultsProvider for WIT bindings.
// It provides the standard mappings between WIT types and Morphir IR types.
type WITDefaults struct{}

// DefaultPrimitives returns the default WIT primitive type mappings.
//
// WIT primitives are mapped to Morphir types as follows:
//   - bool → Bool
//   - u8/u16/u32/u64 → Int (unsigned integers)
//   - s8/s16/s32/s64 → Int (signed integers)
//   - f32/f64 → Float (floating point)
//   - string → String
//   - char → Char
func (WITDefaults) DefaultPrimitives() []typemap.TypeMapping {
	return []typemap.TypeMapping{
		// Boolean
		{
			ExternalType:  "bool",
			MorphirType:   typemap.MorphirTypeRef{PrimitiveKind: "Bool"},
			Bidirectional: true,
			Priority:      0,
		},

		// Unsigned integers - all map to Morphir Int
		{
			ExternalType:  "u8",
			MorphirType:   typemap.MorphirTypeRef{PrimitiveKind: "Int"},
			Bidirectional: false,
			Direction:     typemap.ToMorphir,
			Priority:      0,
		},
		{
			ExternalType:  "u16",
			MorphirType:   typemap.MorphirTypeRef{PrimitiveKind: "Int"},
			Bidirectional: false,
			Direction:     typemap.ToMorphir,
			Priority:      0,
		},
		{
			ExternalType:  "u32",
			MorphirType:   typemap.MorphirTypeRef{PrimitiveKind: "Int"},
			Bidirectional: true, // Default WIT integer
			Priority:      0,
		},
		{
			ExternalType:  "u64",
			MorphirType:   typemap.MorphirTypeRef{PrimitiveKind: "Int"},
			Bidirectional: false,
			Direction:     typemap.ToMorphir,
			Priority:      0,
		},

		// Signed integers - all map to Morphir Int
		{
			ExternalType:  "s8",
			MorphirType:   typemap.MorphirTypeRef{PrimitiveKind: "Int"},
			Bidirectional: false,
			Direction:     typemap.ToMorphir,
			Priority:      0,
		},
		{
			ExternalType:  "s16",
			MorphirType:   typemap.MorphirTypeRef{PrimitiveKind: "Int"},
			Bidirectional: false,
			Direction:     typemap.ToMorphir,
			Priority:      0,
		},
		{
			ExternalType:  "s32",
			MorphirType:   typemap.MorphirTypeRef{PrimitiveKind: "Int"},
			Bidirectional: false,
			Direction:     typemap.ToMorphir,
			Priority:      0,
		},
		{
			ExternalType:  "s64",
			MorphirType:   typemap.MorphirTypeRef{PrimitiveKind: "Int"},
			Bidirectional: false,
			Direction:     typemap.ToMorphir,
			Priority:      0,
		},

		// Floating point
		{
			ExternalType:  "f32",
			MorphirType:   typemap.MorphirTypeRef{PrimitiveKind: "Float"},
			Bidirectional: false,
			Direction:     typemap.ToMorphir,
			Priority:      0,
		},
		{
			ExternalType:  "f64",
			MorphirType:   typemap.MorphirTypeRef{PrimitiveKind: "Float"},
			Bidirectional: true, // Default WIT float
			Priority:      0,
		},

		// String
		{
			ExternalType:  "string",
			MorphirType:   typemap.MorphirTypeRef{PrimitiveKind: "String"},
			Bidirectional: true,
			Priority:      0,
		},

		// Character
		{
			ExternalType:  "char",
			MorphirType:   typemap.MorphirTypeRef{PrimitiveKind: "Char"},
			Bidirectional: true,
			Priority:      0,
		},
	}
}

// DefaultContainers returns the default WIT container type mappings.
//
// WIT containers are mapped to Morphir SDK types as follows:
//   - list<T> → Morphir.SDK:List:List
//   - option<T> → Morphir.SDK:Maybe:Maybe
//   - result<T,E> → Morphir.SDK:Result:Result
//   - tuple → built-in tuple support
func (WITDefaults) DefaultContainers() []typemap.ContainerMapping {
	return []typemap.ContainerMapping{
		// list<T> → List T
		{
			ExternalPattern: "list",
			MorphirPattern:  "Morphir.SDK:List:List",
			TypeParamCount:  1,
			Bidirectional:   true,
			Priority:        0,
		},

		// option<T> → Maybe T
		{
			ExternalPattern: "option",
			MorphirPattern:  "Morphir.SDK:Maybe:Maybe",
			TypeParamCount:  1,
			Bidirectional:   true,
			Priority:        0,
		},

		// result<T, E> → Result E T (note: Morphir's Result has error first)
		{
			ExternalPattern: "result",
			MorphirPattern:  "Morphir.SDK:Result:Result",
			TypeParamCount:  2,
			Bidirectional:   true,
			Priority:        0,
		},

		// tuple<...> → built-in tuple
		{
			ExternalPattern: "tuple",
			MorphirPattern:  "tuple",
			TypeParamCount:  -1, // Variable arity
			Bidirectional:   true,
			Priority:        0,
		},
	}
}

// NewWITRegistry creates a new type mapping registry for WIT bindings.
// It loads the default mappings and applies any configuration overrides.
func NewWITRegistry(cfg typemap.TypeMappingConfig) *typemap.Registry {
	return typemap.NewBuilder(BindingName).
		WithDefaults(WITDefaults{}).
		WithConfig(cfg).
		Build()
}

// DefaultWITRegistry creates a registry with just the default mappings.
func DefaultWITRegistry() *typemap.Registry {
	return NewWITRegistry(typemap.TypeMappingConfig{})
}

// init registers the WIT defaults with the global manager.
func init() {
	typemap.Register(DefaultWITRegistry())
}
