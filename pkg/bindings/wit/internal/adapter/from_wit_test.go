package adapter

import (
	"testing"

	"github.com/finos/morphir/pkg/bindings/wit/domain"
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

// Function adaptation tests

func TestAdaptFunction_NilFunction(t *testing.T) {
	ctx := NewAdapterContext(&wit.Resolve{})

	_, err := adaptFunction(ctx, nil)

	require.Error(t, err)
	var validationErr *ValidationError
	require.ErrorAs(t, err, &validationErr)
	assert.Contains(t, validationErr.Error(), "function cannot be nil")
}

func TestAdaptFunction_NoParamsNoResults(t *testing.T) {
	witFunc := &wit.Function{
		Name:    "do-something",
		Kind:    &wit.Freestanding{},
		Params:  []wit.Param{},
		Results: []wit.Param{},
	}

	ctx := NewAdapterContext(&wit.Resolve{})
	fn, err := adaptFunction(ctx, witFunc)

	require.NoError(t, err)
	assert.Equal(t, "do-something", fn.Name.String())
	assert.Empty(t, fn.Params)
	assert.Empty(t, fn.Results)
	assert.False(t, fn.IsAsync)
}

func TestAdaptFunction_WithParams(t *testing.T) {
	witFunc := &wit.Function{
		Name: "add",
		Kind: &wit.Freestanding{},
		Params: []wit.Param{
			{Name: "a", Type: wit.U32{}},
			{Name: "b", Type: wit.U32{}},
		},
		Results: []wit.Param{},
	}

	ctx := NewAdapterContext(&wit.Resolve{})
	fn, err := adaptFunction(ctx, witFunc)

	require.NoError(t, err)
	assert.Equal(t, "add", fn.Name.String())
	assert.Len(t, fn.Params, 2)
	assert.Equal(t, "a", fn.Params[0].Name.String())
	assert.Equal(t, "b", fn.Params[1].Name.String())
}

func TestAdaptFunction_WithSingleResult(t *testing.T) {
	witFunc := &wit.Function{
		Name:   "get-number",
		Kind:   &wit.Freestanding{},
		Params: []wit.Param{},
		Results: []wit.Param{
			{Name: "", Type: wit.U32{}}, // Single unnamed result
		},
	}

	ctx := NewAdapterContext(&wit.Resolve{})
	fn, err := adaptFunction(ctx, witFunc)

	require.NoError(t, err)
	assert.Equal(t, "get-number", fn.Name.String())
	assert.Len(t, fn.Results, 1)
}

func TestAdaptFunction_WithMultipleResults(t *testing.T) {
	witFunc := &wit.Function{
		Name:   "divide",
		Kind:   &wit.Freestanding{},
		Params: []wit.Param{},
		Results: []wit.Param{
			{Name: "quotient", Type: wit.U32{}},
			{Name: "remainder", Type: wit.U32{}},
		},
	}

	ctx := NewAdapterContext(&wit.Resolve{})
	fn, err := adaptFunction(ctx, witFunc)

	require.NoError(t, err)
	assert.Equal(t, "divide", fn.Name.String())
	assert.Len(t, fn.Results, 2)
}

func TestAdaptFunction_InvalidName(t *testing.T) {
	witFunc := &wit.Function{
		Name:    "INVALID_NAME",
		Kind:    &wit.Freestanding{},
		Params:  []wit.Param{},
		Results: []wit.Param{},
	}

	ctx := NewAdapterContext(&wit.Resolve{})
	_, err := adaptFunction(ctx, witFunc)

	require.Error(t, err)
	var adapterErr *AdapterError
	require.ErrorAs(t, err, &adapterErr)
	assert.Equal(t, "function name", adapterErr.Context)
}

func TestAdaptParam_NamedParam(t *testing.T) {
	witParam := wit.Param{
		Name: "value",
		Type: wit.U32{},
	}

	ctx := NewAdapterContext(&wit.Resolve{})
	param, err := adaptParam(ctx, witParam)

	require.NoError(t, err)
	assert.Equal(t, "value", param.Name.String())
}

func TestAdaptParam_UnnamedParam(t *testing.T) {
	witParam := wit.Param{
		Name: "", // Unnamed parameter
		Type: wit.U32{},
	}

	ctx := NewAdapterContext(&wit.Resolve{})
	param, err := adaptParam(ctx, witParam)

	require.NoError(t, err)
	assert.Equal(t, "", param.Name.String())
}

func TestAdaptParam_InvalidName(t *testing.T) {
	witParam := wit.Param{
		Name: "INVALID_NAME",
		Type: wit.U32{},
	}

	ctx := NewAdapterContext(&wit.Resolve{})
	_, err := adaptParam(ctx, witParam)

	require.Error(t, err)
	var adapterErr *AdapterError
	require.ErrorAs(t, err, &adapterErr)
	assert.Equal(t, "parameter name", adapterErr.Context)
}

// === Type Definition Adapter Tests ===

func TestAdaptTypeDef_RecordType(t *testing.T) {
	datetimeName := "datetime"
	witTypeDef := &wit.TypeDef{
		Name: &datetimeName,
		Kind: &wit.Record{
			Fields: []wit.Field{
				{Name: "seconds", Type: wit.U64{}},
				{Name: "nanoseconds", Type: wit.U32{}},
			},
		},
	}

	ctx := NewAdapterContext(&wit.Resolve{})
	typeDef, err := adaptTypeDef(ctx, witTypeDef)

	require.NoError(t, err)
	assert.Equal(t, "datetime", typeDef.Name.String())

	recordDef, ok := typeDef.Kind.(domain.RecordDef)
	require.True(t, ok, "Kind should be RecordDef")
	assert.Len(t, recordDef.Fields, 2)
	assert.Equal(t, "seconds", recordDef.Fields[0].Name.String())
	assert.Equal(t, "nanoseconds", recordDef.Fields[1].Name.String())
}

func TestAdaptTypeDef_TypeAlias(t *testing.T) {
	instantName := "instant"
	witTypeDef := &wit.TypeDef{
		Name: &instantName,
		Kind: wit.U64{},
	}

	ctx := NewAdapterContext(&wit.Resolve{})
	typeDef, err := adaptTypeDef(ctx, witTypeDef)

	require.NoError(t, err)
	assert.Equal(t, "instant", typeDef.Name.String())

	aliasDef, ok := typeDef.Kind.(domain.TypeAliasDef)
	require.True(t, ok, "Kind should be TypeAliasDef")

	primType, ok := aliasDef.Target.(domain.PrimitiveType)
	require.True(t, ok, "Target should be PrimitiveType")
	assert.Equal(t, domain.U64, primType.Kind)
}

func TestAdaptTypeDef_NilTypeDef(t *testing.T) {
	ctx := NewAdapterContext(&wit.Resolve{})
	_, err := adaptTypeDef(ctx, nil)

	require.Error(t, err)
	var validationErr *ValidationError
	require.ErrorAs(t, err, &validationErr)
}

func TestAdaptTypeDef_MissingName(t *testing.T) {
	witTypeDef := &wit.TypeDef{
		Name: nil,
		Kind: wit.U64{},
	}

	ctx := NewAdapterContext(&wit.Resolve{})
	_, err := adaptTypeDef(ctx, witTypeDef)

	require.Error(t, err)
	var validationErr *ValidationError
	require.ErrorAs(t, err, &validationErr)
}

func TestAdaptTypeDefKind_RecordWithMultipleFields(t *testing.T) {
	witRecord := &wit.Record{
		Fields: []wit.Field{
			{Name: "x", Type: wit.S32{}},
			{Name: "y", Type: wit.S32{}},
			{Name: "z", Type: wit.S32{}},
		},
	}

	ctx := NewAdapterContext(&wit.Resolve{})
	kind, err := adaptTypeDefKindToTypeDefKind(ctx, witRecord)

	require.NoError(t, err)
	recordDef, ok := kind.(domain.RecordDef)
	require.True(t, ok)
	assert.Len(t, recordDef.Fields, 3)
	assert.Equal(t, "x", recordDef.Fields[0].Name.String())
	assert.Equal(t, "y", recordDef.Fields[1].Name.String())
	assert.Equal(t, "z", recordDef.Fields[2].Name.String())
}

func TestAdaptTypeDefKind_EmptyRecord(t *testing.T) {
	witRecord := &wit.Record{
		Fields: []wit.Field{},
	}

	ctx := NewAdapterContext(&wit.Resolve{})
	kind, err := adaptTypeDefKindToTypeDefKind(ctx, witRecord)

	require.NoError(t, err)
	recordDef, ok := kind.(domain.RecordDef)
	require.True(t, ok)
	assert.Len(t, recordDef.Fields, 0)
}

func TestAdaptType_NamedRecordType(t *testing.T) {
	// When we reference a named record type (e.g., "datetime" in function return),
	// it should be converted to a NamedType
	datetimeName := "datetime"
	witTypeDef := &wit.TypeDef{
		Name: &datetimeName,
		Kind: &wit.Record{
			Fields: []wit.Field{
				{Name: "seconds", Type: wit.U64{}},
			},
		},
	}

	ctx := NewAdapterContext(&wit.Resolve{})
	typ, err := adaptType(ctx, witTypeDef)

	require.NoError(t, err)
	namedType, ok := typ.(domain.NamedType)
	require.True(t, ok, "Should be NamedType, not RecordDef")
	assert.Equal(t, "datetime", namedType.Name.String())
}

func TestAdaptTypeDef_VariantType(t *testing.T) {
	resultName := "result"
	witTypeDef := &wit.TypeDef{
		Name: &resultName,
		Kind: &wit.Variant{
			Cases: []wit.Case{
				{Name: "ok", Type: wit.String{}},
				{Name: "err", Type: wit.U32{}},
			},
		},
	}

	ctx := NewAdapterContext(&wit.Resolve{})
	typeDef, err := adaptTypeDef(ctx, witTypeDef)

	require.NoError(t, err)
	assert.Equal(t, "result", typeDef.Name.String())

	variantDef, ok := typeDef.Kind.(domain.VariantDef)
	require.True(t, ok, "Kind should be VariantDef")
	assert.Len(t, variantDef.Cases, 2)
	assert.Equal(t, "ok", variantDef.Cases[0].Name.String())
	assert.NotNil(t, variantDef.Cases[0].Payload)
	assert.Equal(t, "err", variantDef.Cases[1].Name.String())
	assert.NotNil(t, variantDef.Cases[1].Payload)
}

func TestAdaptTypeDef_VariantWithoutPayload(t *testing.T) {
	optionName := "option"
	witTypeDef := &wit.TypeDef{
		Name: &optionName,
		Kind: &wit.Variant{
			Cases: []wit.Case{
				{Name: "none", Type: nil}, // No payload
				{Name: "some", Type: wit.U32{}},
			},
		},
	}

	ctx := NewAdapterContext(&wit.Resolve{})
	typeDef, err := adaptTypeDef(ctx, witTypeDef)

	require.NoError(t, err)
	variantDef, ok := typeDef.Kind.(domain.VariantDef)
	require.True(t, ok, "Kind should be VariantDef")
	assert.Len(t, variantDef.Cases, 2)
	assert.Nil(t, variantDef.Cases[0].Payload, "none case should have no payload")
	assert.NotNil(t, variantDef.Cases[1].Payload, "some case should have payload")
}

func TestAdaptTypeDef_EnumType(t *testing.T) {
	colorName := "color"
	witTypeDef := &wit.TypeDef{
		Name: &colorName,
		Kind: &wit.Enum{
			Cases: []wit.EnumCase{
				{Name: "red"},
				{Name: "green"},
				{Name: "blue"},
			},
		},
	}

	ctx := NewAdapterContext(&wit.Resolve{})
	typeDef, err := adaptTypeDef(ctx, witTypeDef)

	require.NoError(t, err)
	assert.Equal(t, "color", typeDef.Name.String())

	enumDef, ok := typeDef.Kind.(domain.EnumDef)
	require.True(t, ok, "Kind should be EnumDef")
	assert.Len(t, enumDef.Cases, 3)
	assert.Equal(t, "red", enumDef.Cases[0].String())
	assert.Equal(t, "green", enumDef.Cases[1].String())
	assert.Equal(t, "blue", enumDef.Cases[2].String())
}

func TestAdaptTypeDefKind_VariantWithMultipleCases(t *testing.T) {
	witVariant := &wit.Variant{
		Cases: []wit.Case{
			{Name: "success", Type: wit.String{}},
			{Name: "error", Type: wit.U32{}},
			{Name: "pending", Type: nil},
		},
	}

	ctx := NewAdapterContext(&wit.Resolve{})
	kind, err := adaptTypeDefKindToTypeDefKind(ctx, witVariant)

	require.NoError(t, err)
	variantDef, ok := kind.(domain.VariantDef)
	require.True(t, ok)
	assert.Len(t, variantDef.Cases, 3)
	assert.Equal(t, "success", variantDef.Cases[0].Name.String())
	assert.NotNil(t, variantDef.Cases[0].Payload)
	assert.Equal(t, "error", variantDef.Cases[1].Name.String())
	assert.NotNil(t, variantDef.Cases[1].Payload)
	assert.Equal(t, "pending", variantDef.Cases[2].Name.String())
	assert.Nil(t, variantDef.Cases[2].Payload)
}

func TestAdaptTypeDefKind_EmptyEnum(t *testing.T) {
	witEnum := &wit.Enum{
		Cases: []wit.EnumCase{},
	}

	ctx := NewAdapterContext(&wit.Resolve{})
	kind, err := adaptTypeDefKindToTypeDefKind(ctx, witEnum)

	require.NoError(t, err)
	enumDef, ok := kind.(domain.EnumDef)
	require.True(t, ok)
	assert.Len(t, enumDef.Cases, 0)
}

func TestAdaptType_NamedVariantType(t *testing.T) {
	// When we reference a named variant type in a function signature,
	// it should be converted to a NamedType
	resultName := "result"
	witTypeDef := &wit.TypeDef{
		Name: &resultName,
		Kind: &wit.Variant{
			Cases: []wit.Case{
				{Name: "ok", Type: wit.U32{}},
			},
		},
	}

	ctx := NewAdapterContext(&wit.Resolve{})
	typ, err := adaptType(ctx, witTypeDef)

	require.NoError(t, err)
	namedType, ok := typ.(domain.NamedType)
	require.True(t, ok, "Should be NamedType, not VariantDef")
	assert.Equal(t, "result", namedType.Name.String())
}

func TestAdaptType_NamedEnumType(t *testing.T) {
	// When we reference a named enum type in a function signature,
	// it should be converted to a NamedType
	colorName := "color"
	witTypeDef := &wit.TypeDef{
		Name: &colorName,
		Kind: &wit.Enum{
			Cases: []wit.EnumCase{
				{Name: "red"},
			},
		},
	}

	ctx := NewAdapterContext(&wit.Resolve{})
	typ, err := adaptType(ctx, witTypeDef)

	require.NoError(t, err)
	namedType, ok := typ.(domain.NamedType)
	require.True(t, ok, "Should be NamedType, not EnumDef")
	assert.Equal(t, "color", namedType.Name.String())
}

// TODO: Add tests for world items once implemented
// func TestAdaptWorldItem_InterfaceImport(t *testing.T) { }
// func TestAdaptWorldItem_FunctionImport(t *testing.T) { }
// func TestAdaptWorldItem_Export(t *testing.T) { }
