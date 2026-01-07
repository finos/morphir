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
	// TODO: This test is currently skipped because wit.Ident.Version handling
	// needs to be investigated. The bytecodealliance/wit package may have
	// a different way of representing versions.
	t.Skip("Version handling needs investigation - wit.Ident.Version type unclear")

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

// Additional comprehensive adapter tests

func TestFromWIT_MultiplePackages(t *testing.T) {
	pkg1 := &wit.Package{
		Name: wit.Ident{
			Namespace: "test",
			Package:   "pkg1",
		},
	}
	pkg2 := &wit.Package{
		Name: wit.Ident{
			Namespace: "test",
			Package:   "pkg2",
		},
	}

	resolve := &wit.Resolve{
		Packages: []*wit.Package{pkg1, pkg2},
	}

	packages, warnings, err := FromWIT(resolve)

	require.NoError(t, err)
	assert.Empty(t, warnings)
	assert.Len(t, packages, 2)
	assert.Equal(t, "pkg1", packages[0].Name.String())
	assert.Equal(t, "pkg2", packages[1].Name.String())
}

func TestFromWIT_SkipsNilPackages(t *testing.T) {
	pkg1 := &wit.Package{
		Name: wit.Ident{
			Namespace: "test",
			Package:   "valid",
		},
	}

	resolve := &wit.Resolve{
		Packages: []*wit.Package{pkg1, nil, pkg1},
	}

	packages, warnings, err := FromWIT(resolve)

	require.NoError(t, err)
	assert.Empty(t, warnings)
	assert.Len(t, packages, 2)
}

func TestFromWIT_ErrorStopsProcessing(t *testing.T) {
	pkg1 := &wit.Package{
		Name: wit.Ident{
			Namespace: "test",
			Package:   "valid",
		},
	}
	pkg2 := &wit.Package{
		Name: wit.Ident{
			Namespace: "", // Invalid - empty namespace
			Package:   "invalid",
		},
	}

	resolve := &wit.Resolve{
		Packages: []*wit.Package{pkg1, pkg2},
	}

	packages, warnings, err := FromWIT(resolve)

	require.Error(t, err)
	assert.Nil(t, packages)
	assert.NotNil(t, warnings) // Warnings should still be returned
}

func TestAdaptPackage_InvalidPackageName(t *testing.T) {
	witPkg := &wit.Package{
		Name: wit.Ident{
			Namespace: "test",
			Package:   "Invalid-NAME", // uppercase not allowed in package names
		},
	}

	ctx := NewAdapterContext(&wit.Resolve{})
	_, err := adaptPackage(ctx, witPkg)

	require.Error(t, err)
	var adapterErr *AdapterError
	require.ErrorAs(t, err, &adapterErr)
	assert.Equal(t, "package name", adapterErr.Context)
}

func TestAdaptInterface_EmptyName(t *testing.T) {
	witIface := &wit.Interface{}

	ctx := NewAdapterContext(&wit.Resolve{})
	_, err := adaptInterface(ctx, "", witIface)

	require.Error(t, err)
}

func TestAdaptInterface_InvalidNameUppercase(t *testing.T) {
	witIface := &wit.Interface{}

	ctx := NewAdapterContext(&wit.Resolve{})
	_, err := adaptInterface(ctx, "INVALID_NAME", witIface)

	require.Error(t, err)
	var adapterErr *AdapterError
	require.ErrorAs(t, err, &adapterErr)
	assert.Equal(t, "interface name", adapterErr.Context)
}

func TestAdaptWorld_EmptyName(t *testing.T) {
	witWorld := &wit.World{}

	ctx := NewAdapterContext(&wit.Resolve{})
	_, err := adaptWorld(ctx, "", witWorld)

	require.Error(t, err)
}

func TestAdaptWorld_InvalidName(t *testing.T) {
	witWorld := &wit.World{}

	ctx := NewAdapterContext(&wit.Resolve{})
	_, err := adaptWorld(ctx, "INVALID_NAME", witWorld)

	require.Error(t, err)
	var adapterErr *AdapterError
	require.ErrorAs(t, err, &adapterErr)
	assert.Equal(t, "world name", adapterErr.Context)
}

func TestAdapterContext_WarningAccumulation(t *testing.T) {
	ctx := NewAdapterContext(&wit.Resolve{})

	assert.Empty(t, ctx.Warnings)

	ctx.AddWarning("warning 1")
	assert.Len(t, ctx.Warnings, 1)

	ctx.AddWarning("warning %d", 2)
	assert.Len(t, ctx.Warnings, 2)
	assert.Equal(t, "warning 1", ctx.Warnings[0])
	assert.Equal(t, "warning 2", ctx.Warnings[1])
}

func TestAdapterContext_StrictModeImmutability(t *testing.T) {
	ctx := NewAdapterContext(&wit.Resolve{})
	assert.False(t, ctx.Strict)

	strictCtx := ctx.WithStrict()
	assert.True(t, strictCtx.Strict)
	assert.False(t, ctx.Strict) // Original should be unchanged

	// Warnings should be independent
	ctx.AddWarning("original warning")
	assert.Len(t, ctx.Warnings, 1)
	assert.Empty(t, strictCtx.Warnings) // Strict context gets a shallow copy of warnings
}

func TestAdapterError_ContextualInformation(t *testing.T) {
	cause := assert.AnError
	err := newAdapterError("type", "my-type", cause)

	assert.Contains(t, err.Error(), "type")
	assert.Contains(t, err.Error(), "my-type")
	assert.Contains(t, err.Error(), cause.Error())

	// Test error unwrapping
	assert.ErrorIs(t, err, cause)
}

func TestValidationError_WithoutItem(t *testing.T) {
	err := newValidationError("", "general validation error")

	assert.Contains(t, err.Error(), "general validation error")
	assert.NotContains(t, err.Error(), "for ")
}

// Type adaptation tests
//
// Note: The bytecodealliance/wit package has an unusual type hierarchy where
// composite types like List, Option, Result don't implement wit.Type,
// making them difficult to construct programmatically in unit tests.
// We test the adapter implementation here with what we can construct,
// and defer comprehensive type testing to integration tests with real WIT packages.

func TestAdaptType_NilType(t *testing.T) {
	ctx := NewAdapterContext(&wit.Resolve{})

	_, err := adaptType(ctx, nil)

	require.Error(t, err)
	var validationErr *ValidationError
	require.ErrorAs(t, err, &validationErr)
	assert.Contains(t, validationErr.Error(), "type cannot be nil")
}

// TODO: Add tests for function adaptation once implemented
// func TestAdaptFunction_NoParams(t *testing.T) { }
// func TestAdaptFunction_WithParams(t *testing.T) { }
// func TestAdaptFunction_WithResults(t *testing.T) { }
// func TestAdaptFunction_Async(t *testing.T) { }

// TODO: Add tests for world items once implemented
// func TestAdaptWorldItem_InterfaceImport(t *testing.T) { }
// func TestAdaptWorldItem_FunctionImport(t *testing.T) { }
// func TestAdaptWorldItem_Export(t *testing.T) { }
