package parser

import (
	"testing"

	"github.com/finos/morphir/pkg/bindings/wit/domain"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestParsePackageDeclaration(t *testing.T) {
	input := `package wasi:clocks@0.2.0;`

	parser := NewParser(input)
	pkg, err := parser.Parse()
	require.NoError(t, err)

	assert.Equal(t, "wasi", pkg.Namespace.String())
	assert.Equal(t, "clocks", pkg.Name.String())
	require.NotNil(t, pkg.Version)
	assert.Equal(t, "0.2.0", pkg.Version.String())
}

func TestParseInterface(t *testing.T) {
	input := `package test:pkg@1.0.0;

interface calculator {
    add: func(a: u32, b: u32) -> u32;
}`

	parser := NewParser(input)
	pkg, err := parser.Parse()
	require.NoError(t, err)

	require.Len(t, pkg.Interfaces, 1)
	iface := pkg.Interfaces[0]
	assert.Equal(t, "calculator", iface.Name.String())
	require.Len(t, iface.Functions, 1)

	fn := iface.Functions[0]
	assert.Equal(t, "add", fn.Name.String())
	require.Len(t, fn.Params, 2)
	assert.Equal(t, "a", fn.Params[0].Name.String())
	assert.Equal(t, "b", fn.Params[1].Name.String())
	require.Len(t, fn.Results, 1)
}

func TestParseRecord(t *testing.T) {
	input := `package test:pkg@1.0.0;

interface types {
    record point {
        x: s32,
        y: s32,
    }
}`

	parser := NewParser(input)
	pkg, err := parser.Parse()
	require.NoError(t, err)

	require.Len(t, pkg.Interfaces, 1)
	require.Len(t, pkg.Interfaces[0].Types, 1)

	td := pkg.Interfaces[0].Types[0]
	assert.Equal(t, "point", td.Name.String())

	recordDef, ok := td.Kind.(domain.RecordDef)
	require.True(t, ok)
	require.Len(t, recordDef.Fields, 2)
	assert.Equal(t, "x", recordDef.Fields[0].Name.String())
	assert.Equal(t, "y", recordDef.Fields[1].Name.String())
}

func TestParseEnum(t *testing.T) {
	input := `package test:pkg@1.0.0;

interface types {
    enum color {
        red,
        green,
        blue,
    }
}`

	parser := NewParser(input)
	pkg, err := parser.Parse()
	require.NoError(t, err)

	require.Len(t, pkg.Interfaces[0].Types, 1)
	td := pkg.Interfaces[0].Types[0]
	assert.Equal(t, "color", td.Name.String())

	enumDef, ok := td.Kind.(domain.EnumDef)
	require.True(t, ok)
	require.Len(t, enumDef.Cases, 3)
	assert.Equal(t, "red", enumDef.Cases[0].String())
	assert.Equal(t, "green", enumDef.Cases[1].String())
	assert.Equal(t, "blue", enumDef.Cases[2].String())
}

func TestParseVariant(t *testing.T) {
	input := `package test:pkg@1.0.0;

interface types {
    variant result {
        ok(string),
        err,
    }
}`

	parser := NewParser(input)
	pkg, err := parser.Parse()
	require.NoError(t, err)

	require.Len(t, pkg.Interfaces[0].Types, 1)
	td := pkg.Interfaces[0].Types[0]
	assert.Equal(t, "result", td.Name.String())

	variantDef, ok := td.Kind.(domain.VariantDef)
	require.True(t, ok)
	require.Len(t, variantDef.Cases, 2)

	assert.Equal(t, "ok", variantDef.Cases[0].Name.String())
	require.NotNil(t, variantDef.Cases[0].Payload)

	assert.Equal(t, "err", variantDef.Cases[1].Name.String())
	assert.Nil(t, variantDef.Cases[1].Payload)
}

func TestParseFlags(t *testing.T) {
	input := `package test:pkg@1.0.0;

interface types {
    flags permissions {
        read,
        write,
        execute,
    }
}`

	parser := NewParser(input)
	pkg, err := parser.Parse()
	require.NoError(t, err)

	require.Len(t, pkg.Interfaces[0].Types, 1)
	td := pkg.Interfaces[0].Types[0]
	assert.Equal(t, "permissions", td.Name.String())

	flagsDef, ok := td.Kind.(domain.FlagsDef)
	require.True(t, ok)
	require.Len(t, flagsDef.Flags, 3)
	assert.Equal(t, "read", flagsDef.Flags[0].String())
	assert.Equal(t, "write", flagsDef.Flags[1].String())
	assert.Equal(t, "execute", flagsDef.Flags[2].String())
}

func TestParseTypeAlias(t *testing.T) {
	input := `package test:pkg@1.0.0;

interface types {
    type my-int = u32;
}`

	parser := NewParser(input)
	pkg, err := parser.Parse()
	require.NoError(t, err)

	require.Len(t, pkg.Interfaces[0].Types, 1)
	td := pkg.Interfaces[0].Types[0]
	assert.Equal(t, "my-int", td.Name.String())

	aliasDef, ok := td.Kind.(domain.TypeAliasDef)
	require.True(t, ok)

	primType, ok := aliasDef.Target.(domain.PrimitiveType)
	require.True(t, ok)
	assert.Equal(t, domain.U32, primType.Kind)
}

func TestParseResource(t *testing.T) {
	input := `package test:pkg@1.0.0;

interface types {
    resource file {
        constructor();
        read: func(len: u64) -> list<u8>;
        write: func(data: list<u8>) -> u64;
        close: static func();
    }
}`

	parser := NewParser(input)
	pkg, err := parser.Parse()
	require.NoError(t, err)

	require.Len(t, pkg.Interfaces[0].Types, 1)
	td := pkg.Interfaces[0].Types[0]
	assert.Equal(t, "file", td.Name.String())

	resourceDef, ok := td.Kind.(domain.ResourceDef)
	require.True(t, ok)
	require.NotNil(t, resourceDef.Constructor)
	require.Len(t, resourceDef.Methods, 3)

	assert.Equal(t, "read", resourceDef.Methods[0].Name.String())
	assert.False(t, resourceDef.Methods[0].IsStatic)

	assert.Equal(t, "write", resourceDef.Methods[1].Name.String())
	assert.False(t, resourceDef.Methods[1].IsStatic)

	assert.Equal(t, "close", resourceDef.Methods[2].Name.String())
	assert.True(t, resourceDef.Methods[2].IsStatic)
}

func TestParseWorld(t *testing.T) {
	input := `package test:pkg@1.0.0;

interface my-iface {
}

world my-world {
    import my-iface;
    export my-iface;
}`

	parser := NewParser(input)
	pkg, err := parser.Parse()
	require.NoError(t, err)

	require.Len(t, pkg.Worlds, 1)
	world := pkg.Worlds[0]
	assert.Equal(t, "my-world", world.Name.String())
	require.Len(t, world.Imports, 1)
	require.Len(t, world.Exports, 1)
}

func TestParseContainerTypes(t *testing.T) {
	tests := []struct {
		name     string
		typeStr  string
		validate func(t *testing.T, ty domain.Type)
	}{
		{
			name:    "list",
			typeStr: "list<u8>",
			validate: func(t *testing.T, ty domain.Type) {
				listType, ok := ty.(domain.ListType)
				require.True(t, ok)
				primType, ok := listType.Element.(domain.PrimitiveType)
				require.True(t, ok)
				assert.Equal(t, domain.U8, primType.Kind)
			},
		},
		{
			name:    "option",
			typeStr: "option<string>",
			validate: func(t *testing.T, ty domain.Type) {
				optType, ok := ty.(domain.OptionType)
				require.True(t, ok)
				primType, ok := optType.Inner.(domain.PrimitiveType)
				require.True(t, ok)
				assert.Equal(t, domain.String, primType.Kind)
			},
		},
		{
			name:    "result with both",
			typeStr: "result<string, u32>",
			validate: func(t *testing.T, ty domain.Type) {
				resType, ok := ty.(domain.ResultType)
				require.True(t, ok)
				require.NotNil(t, resType.Ok)
				require.NotNil(t, resType.Err)
			},
		},
		{
			name:    "result with only ok",
			typeStr: "result<string>",
			validate: func(t *testing.T, ty domain.Type) {
				resType, ok := ty.(domain.ResultType)
				require.True(t, ok)
				require.NotNil(t, resType.Ok)
				assert.Nil(t, resType.Err)
			},
		},
		{
			name:    "result with only err",
			typeStr: "result<_, u32>",
			validate: func(t *testing.T, ty domain.Type) {
				resType, ok := ty.(domain.ResultType)
				require.True(t, ok)
				assert.Nil(t, resType.Ok)
				require.NotNil(t, resType.Err)
			},
		},
		{
			name:    "bare result",
			typeStr: "result",
			validate: func(t *testing.T, ty domain.Type) {
				resType, ok := ty.(domain.ResultType)
				require.True(t, ok)
				assert.Nil(t, resType.Ok)
				assert.Nil(t, resType.Err)
			},
		},
		{
			name:    "tuple",
			typeStr: "tuple<u32, string>",
			validate: func(t *testing.T, ty domain.Type) {
				tupleType, ok := ty.(domain.TupleType)
				require.True(t, ok)
				require.Len(t, tupleType.Types, 2)
			},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			input := `package test:pkg@1.0.0;
interface types {
    foo: func() -> ` + tt.typeStr + `;
}`
			parser := NewParser(input)
			pkg, err := parser.Parse()
			require.NoError(t, err)

			require.Len(t, pkg.Interfaces[0].Functions, 1)
			fn := pkg.Interfaces[0].Functions[0]
			require.Len(t, fn.Results, 1)
			tt.validate(t, fn.Results[0])
		})
	}
}

func TestParseHandleTypes(t *testing.T) {
	input := `package test:pkg@1.0.0;

interface types {
    resource file {
    }

    open: func() -> own<file>;
    use-file: func(f: borrow<file>);
}`

	parser := NewParser(input)
	pkg, err := parser.Parse()
	require.NoError(t, err)

	require.Len(t, pkg.Interfaces[0].Functions, 2)

	// Check own<file>
	fn1 := pkg.Interfaces[0].Functions[0]
	require.Len(t, fn1.Results, 1)
	handleType, ok := fn1.Results[0].(domain.HandleType)
	require.True(t, ok)
	assert.Equal(t, "file", handleType.Resource.String())
	assert.False(t, handleType.IsBorrow)

	// Check borrow<file>
	fn2 := pkg.Interfaces[0].Functions[1]
	require.Len(t, fn2.Params, 1)
	handleType, ok = fn2.Params[0].Type.(domain.HandleType)
	require.True(t, ok)
	assert.Equal(t, "file", handleType.Resource.String())
	assert.True(t, handleType.IsBorrow)
}

func TestParseWASIClocks(t *testing.T) {
	input := `// WASI Clocks - simplified version for testing
package wasi:clocks@0.2.0;

interface wall-clock {
    record datetime {
        seconds: u64,
        nanoseconds: u32,
    }

    now: func() -> datetime;
    resolution: func() -> datetime;
}

interface monotonic-clock {
    type instant = u64;
    type duration = u64;

    now: func() -> instant;
    resolution: func() -> duration;
    subscribe-instant: func(when: instant) -> u64;
    subscribe-duration: func(when: duration) -> u64;
}

world clocks {
    import wall-clock;
    import monotonic-clock;
}`

	parser := NewParser(input)
	pkg, err := parser.Parse()
	require.NoError(t, err)

	assert.Equal(t, "wasi", pkg.Namespace.String())
	assert.Equal(t, "clocks", pkg.Name.String())
	assert.Equal(t, "0.2.0", pkg.Version.String())

	require.Len(t, pkg.Interfaces, 2)
	assert.Equal(t, "wall-clock", pkg.Interfaces[0].Name.String())
	assert.Equal(t, "monotonic-clock", pkg.Interfaces[1].Name.String())

	require.Len(t, pkg.Worlds, 1)
	assert.Equal(t, "clocks", pkg.Worlds[0].Name.String())
}

func TestParseEscapedKeywords(t *testing.T) {
	// In WIT, % prefix allows using keywords as identifiers
	input := `package test:pkg@1.0.0;

interface types {
    record stat {
        %type: string,
    }
}`

	parser := NewParser(input)
	pkg, err := parser.Parse()
	require.NoError(t, err)

	require.Len(t, pkg.Interfaces[0].Types, 1)
	td := pkg.Interfaces[0].Types[0]

	recordDef, ok := td.Kind.(domain.RecordDef)
	require.True(t, ok)
	require.Len(t, recordDef.Fields, 1)
	assert.Equal(t, "type", recordDef.Fields[0].Name.String())
}
