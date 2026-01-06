package adapter

import (
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"go.bytecodealliance.org/wit"
)

func TestFromWIT_NilResolve(t *testing.T) {
	packages, warnings, err := FromWIT(nil)

	assert.Nil(t, packages)
	assert.Nil(t, warnings)
	require.Error(t, err)
	assert.Contains(t, err.Error(), "resolve cannot be nil")
}

func TestFromWIT_EmptyResolve(t *testing.T) {
	resolve := &wit.Resolve{
		Packages: make([]*wit.Package, 0),
	}

	packages, warnings, err := FromWIT(resolve)

	require.NoError(t, err)
	assert.Empty(t, packages)
	assert.Empty(t, warnings)
}

func TestAdaptPackage_SimplePackage(t *testing.T) {
	// Create a simple WIT package programmatically
	witPkg := &wit.Package{
		Name: wit.Ident{
			Namespace: "test",
			Package:   "simple",
		},
	}

	ctx := NewAdapterContext(&wit.Resolve{})
	pkg, err := adaptPackage(ctx, witPkg)

	require.NoError(t, err)
	assert.Equal(t, "test", pkg.Namespace.String())
	assert.Equal(t, "simple", pkg.Name.String())
	assert.Nil(t, pkg.Version)
	assert.Empty(t, pkg.Interfaces)
	assert.Empty(t, pkg.Worlds)
}

func TestAdaptPackage_WithVersion(t *testing.T) {
	// semver.Version from github.com/Masterminds/semver/v3
	version, _ := require.New(t).NotNil(nil) // We'll construct manually
	_ = version                              // unused for now - TODO: fix when implementing

	witPkg := &wit.Package{
		Name: wit.Ident{
			Namespace: "wasi",
			Package:   "clocks",
			// Version will need proper semver construction
		},
	}

	ctx := NewAdapterContext(&wit.Resolve{})
	pkg, err := adaptPackage(ctx, witPkg)

	require.NoError(t, err)
	assert.Equal(t, "wasi", pkg.Namespace.String())
	assert.Equal(t, "clocks", pkg.Name.String())
	// TODO: Add version assertion when we figure out version construction
}

func TestAdaptPackage_InvalidNamespace(t *testing.T) {
	witPkg := &wit.Package{
		Name: wit.Ident{
			Namespace: "Invalid-NAMESPACE", // uppercase not allowed
			Package:   "test",
		},
	}

	ctx := NewAdapterContext(&wit.Resolve{})
	_, err := adaptPackage(ctx, witPkg)

	require.Error(t, err)
	var adapterErr *AdapterError
	require.ErrorAs(t, err, &adapterErr)
	assert.Equal(t, "package namespace", adapterErr.Context)
}

func TestAdaptPackage_EmptyNamespace(t *testing.T) {
	witPkg := &wit.Package{
		Name: wit.Ident{
			Namespace: "",
			Package:   "test",
		},
	}

	ctx := NewAdapterContext(&wit.Resolve{})
	_, err := adaptPackage(ctx, witPkg)

	require.Error(t, err)
	var validationErr *ValidationError
	require.ErrorAs(t, err, &validationErr)
	assert.Contains(t, validationErr.Error(), "namespace is empty")
}

func TestAdaptInterface_SimpleName(t *testing.T) {
	witIface := &wit.Interface{
		// Empty interface for now
	}

	ctx := NewAdapterContext(&wit.Resolve{})
	iface, err := adaptInterface(ctx, "test-interface", witIface)

	require.NoError(t, err)
	assert.Equal(t, "test-interface", iface.Name.String())
	assert.Empty(t, iface.Types)
	assert.Empty(t, iface.Functions)
	assert.Empty(t, iface.Uses)
}

func TestAdaptInterface_InvalidName(t *testing.T) {
	witIface := &wit.Interface{}

	ctx := NewAdapterContext(&wit.Resolve{})
	_, err := adaptInterface(ctx, "Invalid_Name", witIface)

	require.Error(t, err)
	var adapterErr *AdapterError
	require.ErrorAs(t, err, &adapterErr)
	assert.Equal(t, "interface name", adapterErr.Context)
}

func TestAdaptWorld_SimpleName(t *testing.T) {
	witWorld := &wit.World{
		// Empty world for now
	}

	ctx := NewAdapterContext(&wit.Resolve{})
	world, err := adaptWorld(ctx, "test-world", witWorld)

	require.NoError(t, err)
	assert.Equal(t, "test-world", world.Name.String())
	assert.Empty(t, world.Imports)
	assert.Empty(t, world.Exports)
	assert.Empty(t, world.Uses)
}

func TestAdapterContext_Warnings(t *testing.T) {
	ctx := NewAdapterContext(&wit.Resolve{})

	assert.Empty(t, ctx.Warnings)
	assert.False(t, ctx.Strict)

	ctx.AddWarning("test warning %d", 1)
	ctx.AddWarning("another warning")

	assert.Len(t, ctx.Warnings, 2)
	assert.Equal(t, "test warning 1", ctx.Warnings[0])
	assert.Equal(t, "another warning", ctx.Warnings[1])
}

func TestAdapterContext_StrictMode(t *testing.T) {
	ctx := NewAdapterContext(&wit.Resolve{})
	assert.False(t, ctx.Strict)

	strictCtx := ctx.WithStrict()
	assert.True(t, strictCtx.Strict)
	assert.False(t, ctx.Strict) // Original unchanged
}

func TestAdapterError_Error(t *testing.T) {
	err := newAdapterError("test context", "test-item", assert.AnError)
	assert.Contains(t, err.Error(), "test context")
	assert.Contains(t, err.Error(), "test-item")
	assert.Contains(t, err.Error(), assert.AnError.Error())
}

func TestAdapterError_Unwrap(t *testing.T) {
	cause := assert.AnError
	err := newAdapterError("context", "item", cause)

	assert.ErrorIs(t, err, cause)
}

func TestValidationError_Error(t *testing.T) {
	err := newValidationError("test-item", "something is wrong")
	assert.Contains(t, err.Error(), "test-item")
	assert.Contains(t, err.Error(), "something is wrong")
}

// TODO: Add tests for type adaptation once implemented
// func TestAdaptType_Primitive(t *testing.T) { }
// func TestAdaptType_List(t *testing.T) { }
// func TestAdaptType_Option(t *testing.T) { }
// func TestAdaptType_Result(t *testing.T) { }
// func TestAdaptType_Record(t *testing.T) { }
// func TestAdaptType_Variant(t *testing.T) { }

// TODO: Add tests for function adaptation once implemented
// func TestAdaptFunction_NoParams(t *testing.T) { }
// func TestAdaptFunction_WithParams(t *testing.T) { }
// func TestAdaptFunction_WithResults(t *testing.T) { }
// func TestAdaptFunction_Async(t *testing.T) { }

// TODO: Add tests for world items once implemented
// func TestAdaptWorldItem_InterfaceImport(t *testing.T) { }
// func TestAdaptWorldItem_FunctionImport(t *testing.T) { }
// func TestAdaptWorldItem_Export(t *testing.T) { }
