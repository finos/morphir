package emitter

import (
	"strings"
	"testing"

	"github.com/Masterminds/semver/v3"
	"github.com/finos/morphir/pkg/bindings/wit/domain"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestEmitPrimitiveTypes(t *testing.T) {
	tests := []struct {
		kind     domain.PrimitiveKind
		expected string
	}{
		{domain.U8, "u8"},
		{domain.U16, "u16"},
		{domain.U32, "u32"},
		{domain.U64, "u64"},
		{domain.S8, "s8"},
		{domain.S16, "s16"},
		{domain.S32, "s32"},
		{domain.S64, "s64"},
		{domain.F32, "f32"},
		{domain.F64, "f64"},
		{domain.Bool, "bool"},
		{domain.Char, "char"},
		{domain.String, "string"},
	}

	for _, tt := range tests {
		t.Run(tt.expected, func(t *testing.T) {
			result := emitType(domain.PrimitiveType{Kind: tt.kind})
			assert.Equal(t, tt.expected, result)
		})
	}
}

func TestEmitContainerTypes(t *testing.T) {
	t.Run("list", func(t *testing.T) {
		result := emitType(domain.ListType{
			Element: domain.PrimitiveType{Kind: domain.U8},
		})
		assert.Equal(t, "list<u8>", result)
	})

	t.Run("option", func(t *testing.T) {
		result := emitType(domain.OptionType{
			Inner: domain.PrimitiveType{Kind: domain.String},
		})
		assert.Equal(t, "option<string>", result)
	})

	t.Run("result with both", func(t *testing.T) {
		ok := domain.Type(domain.PrimitiveType{Kind: domain.String})
		err := domain.Type(domain.PrimitiveType{Kind: domain.U32})
		result := emitType(domain.ResultType{Ok: &ok, Err: &err})
		assert.Equal(t, "result<string, u32>", result)
	})

	t.Run("result with only ok", func(t *testing.T) {
		ok := domain.Type(domain.PrimitiveType{Kind: domain.String})
		result := emitType(domain.ResultType{Ok: &ok, Err: nil})
		assert.Equal(t, "result<string>", result)
	})

	t.Run("result with only err", func(t *testing.T) {
		err := domain.Type(domain.PrimitiveType{Kind: domain.U32})
		result := emitType(domain.ResultType{Ok: nil, Err: &err})
		assert.Equal(t, "result<_, u32>", result)
	})

	t.Run("tuple", func(t *testing.T) {
		result := emitType(domain.TupleType{
			Types: []domain.Type{
				domain.PrimitiveType{Kind: domain.U32},
				domain.PrimitiveType{Kind: domain.String},
			},
		})
		assert.Equal(t, "tuple<u32, string>", result)
	})

	t.Run("borrow handle", func(t *testing.T) {
		result := emitType(domain.HandleType{
			Resource: mustNewIdentifier("file"),
			IsBorrow: true,
		})
		assert.Equal(t, "borrow<file>", result)
	})

	t.Run("own handle", func(t *testing.T) {
		result := emitType(domain.HandleType{
			Resource: mustNewIdentifier("descriptor"),
			IsBorrow: false,
		})
		assert.Equal(t, "own<descriptor>", result)
	})
}

func TestEmitTypeDef(t *testing.T) {
	t.Run("record", func(t *testing.T) {
		td := domain.TypeDef{
			Name: mustNewIdentifier("point"),
			Kind: domain.RecordDef{
				Fields: []domain.Field{
					{Name: mustNewIdentifier("x"), Type: domain.PrimitiveType{Kind: domain.S32}},
					{Name: mustNewIdentifier("y"), Type: domain.PrimitiveType{Kind: domain.S32}},
				},
			},
		}
		result := emitTypeDef(td, 0)
		assert.Contains(t, result, "record point {")
		assert.Contains(t, result, "x: s32,")
		assert.Contains(t, result, "y: s32,")
	})

	t.Run("enum", func(t *testing.T) {
		td := domain.TypeDef{
			Name: mustNewIdentifier("color"),
			Kind: domain.EnumDef{
				Cases: []domain.Identifier{
					mustNewIdentifier("red"),
					mustNewIdentifier("green"),
					mustNewIdentifier("blue"),
				},
			},
		}
		result := emitTypeDef(td, 0)
		assert.Contains(t, result, "enum color {")
		assert.Contains(t, result, "red,")
		assert.Contains(t, result, "green,")
		assert.Contains(t, result, "blue,")
	})

	t.Run("variant", func(t *testing.T) {
		payload := domain.Type(domain.PrimitiveType{Kind: domain.String})
		td := domain.TypeDef{
			Name: mustNewIdentifier("result"),
			Kind: domain.VariantDef{
				Cases: []domain.VariantCase{
					{Name: mustNewIdentifier("ok"), Payload: &payload},
					{Name: mustNewIdentifier("err"), Payload: nil},
				},
			},
		}
		result := emitTypeDef(td, 0)
		assert.Contains(t, result, "variant result {")
		assert.Contains(t, result, "ok(string),")
		assert.Contains(t, result, "err,")
	})

	t.Run("flags", func(t *testing.T) {
		td := domain.TypeDef{
			Name: mustNewIdentifier("permissions"),
			Kind: domain.FlagsDef{
				Flags: []domain.Identifier{
					mustNewIdentifier("read"),
					mustNewIdentifier("write"),
					mustNewIdentifier("execute"),
				},
			},
		}
		result := emitTypeDef(td, 0)
		assert.Contains(t, result, "flags permissions {")
		assert.Contains(t, result, "read,")
		assert.Contains(t, result, "write,")
		assert.Contains(t, result, "execute,")
	})

	t.Run("type alias", func(t *testing.T) {
		td := domain.TypeDef{
			Name: mustNewIdentifier("my-size"),
			Kind: domain.TypeAliasDef{
				Target: domain.PrimitiveType{Kind: domain.U32},
			},
		}
		result := emitTypeDef(td, 0)
		assert.Contains(t, result, "type my-size = u32;")
	})
}

func TestEmitFunction(t *testing.T) {
	t.Run("no params no results", func(t *testing.T) {
		fn := domain.Function{
			Name: mustNewIdentifier("run"),
		}
		result := emitFunction(fn, 0)
		assert.Contains(t, result, "run: func();")
	})

	t.Run("with params and result", func(t *testing.T) {
		fn := domain.Function{
			Name: mustNewIdentifier("add"),
			Params: []domain.Param{
				{Name: mustNewIdentifier("a"), Type: domain.PrimitiveType{Kind: domain.U32}},
				{Name: mustNewIdentifier("b"), Type: domain.PrimitiveType{Kind: domain.U32}},
			},
			Results: []domain.Type{domain.PrimitiveType{Kind: domain.U32}},
		}
		result := emitFunction(fn, 0)
		assert.Contains(t, result, "add: func(a: u32, b: u32) -> u32;")
	})
}

func TestEmitInterface(t *testing.T) {
	iface := domain.Interface{
		Name: mustNewIdentifier("calculator"),
		Types: []domain.TypeDef{
			{
				Name: mustNewIdentifier("result"),
				Kind: domain.TypeAliasDef{Target: domain.PrimitiveType{Kind: domain.S64}},
			},
		},
		Functions: []domain.Function{
			{
				Name: mustNewIdentifier("add"),
				Params: []domain.Param{
					{Name: mustNewIdentifier("a"), Type: domain.PrimitiveType{Kind: domain.S64}},
					{Name: mustNewIdentifier("b"), Type: domain.PrimitiveType{Kind: domain.S64}},
				},
				Results: []domain.Type{domain.NamedType{Name: mustNewIdentifier("result")}},
			},
		},
	}

	result := emitInterface(iface, 0)
	assert.Contains(t, result, "interface calculator {")
	assert.Contains(t, result, "type result = s64;")
	assert.Contains(t, result, "add: func(a: s64, b: s64) -> result;")
	assert.Contains(t, result, "}")
}

func TestEmitPackage(t *testing.T) {
	version := semver.MustParse("0.1.0")
	pkg := domain.Package{
		Namespace: mustNewNamespace("example"),
		Name:      mustNewPackageName("calculator"),
		Version:   version,
		Interfaces: []domain.Interface{
			{
				Name: mustNewIdentifier("ops"),
				Functions: []domain.Function{
					{
						Name: mustNewIdentifier("add"),
						Params: []domain.Param{
							{Name: mustNewIdentifier("a"), Type: domain.PrimitiveType{Kind: domain.U32}},
							{Name: mustNewIdentifier("b"), Type: domain.PrimitiveType{Kind: domain.U32}},
						},
						Results: []domain.Type{domain.PrimitiveType{Kind: domain.U32}},
					},
				},
			},
		},
	}

	result := EmitPackage(pkg)

	// Check package declaration
	assert.True(t, strings.HasPrefix(result, "package example:calculator@0.1.0;"))

	// Check interface
	assert.Contains(t, result, "interface ops {")
	assert.Contains(t, result, "add: func(a: u32, b: u32) -> u32;")
}

// Helper functions
func mustNewIdentifier(s string) domain.Identifier {
	id, err := domain.NewIdentifier(s)
	if err != nil {
		panic(err)
	}
	return id
}

func mustNewNamespace(s string) domain.Namespace {
	ns, err := domain.NewNamespace(s)
	if err != nil {
		panic(err)
	}
	return ns
}

func mustNewPackageName(s string) domain.PackageName {
	pn, err := domain.NewPackageName(s)
	if err != nil {
		panic(err)
	}
	return pn
}

func TestRoundTrip(t *testing.T) {
	// This test ensures that we can emit and then parse back to get the same structure
	// For now, we just ensure the emitter produces valid WIT-like output

	version := semver.MustParse("0.2.0")
	original := domain.Package{
		Namespace: mustNewNamespace("wasi"),
		Name:      mustNewPackageName("clocks"),
		Version:   version,
		Interfaces: []domain.Interface{
			{
				Name: mustNewIdentifier("wall-clock"),
				Types: []domain.TypeDef{
					{
						Name: mustNewIdentifier("datetime"),
						Kind: domain.RecordDef{
							Fields: []domain.Field{
								{Name: mustNewIdentifier("seconds"), Type: domain.PrimitiveType{Kind: domain.U64}},
								{Name: mustNewIdentifier("nanoseconds"), Type: domain.PrimitiveType{Kind: domain.U32}},
							},
						},
					},
				},
				Functions: []domain.Function{
					{
						Name:    mustNewIdentifier("now"),
						Results: []domain.Type{domain.NamedType{Name: mustNewIdentifier("datetime")}},
					},
					{
						Name:    mustNewIdentifier("resolution"),
						Results: []domain.Type{domain.NamedType{Name: mustNewIdentifier("datetime")}},
					},
				},
			},
		},
	}

	result := EmitPackage(original)

	// Verify the structure
	require.Contains(t, result, "package wasi:clocks@0.2.0;")
	require.Contains(t, result, "interface wall-clock {")
	require.Contains(t, result, "record datetime {")
	require.Contains(t, result, "seconds: u64,")
	require.Contains(t, result, "nanoseconds: u32,")
	require.Contains(t, result, "now: func() -> datetime;")
	require.Contains(t, result, "resolution: func() -> datetime;")
}
