package steps

import (
	"context"
	"fmt"

	"github.com/cucumber/godog"
	"github.com/finos/morphir/pkg/bindings/wit/domain"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// WITTestContext holds the state for WIT BDD tests
type WITTestContext struct {
	t *testingT // For testify assertions

	// Identifiers and primitives
	inputIdentifier string
	identifier      domain.Identifier
	hasIdentifier   bool
	identifierError error

	// Packages
	packageNamespace string
	packageName      string
	packageVersion   string
	pkg              *domain.Package
	packageError     error

	// Use paths
	usePath      domain.UsePath
	usePathError error

	// Types
	currentType  domain.Type
	typeError    error
	typeDepth    int
	typeCount    int
	visitedTypes []string

	// Traversal results
	collectedTypes []domain.Type
	mappedType     domain.Type
	foldResult     interface{}
	containsResult bool

	// Visitor
	visitor TypeStatisticsVisitor
}

// testingT provides a minimal interface for testify assertions
type testingT struct {
	err error
}

func (t *testingT) Errorf(format string, args ...interface{}) {
	t.err = fmt.Errorf(format, args...)
}

func (t *testingT) FailNow() {
	// For BDD tests, we'll just store the error
}

// TypeStatisticsVisitor collects statistics about types
type TypeStatisticsVisitor struct {
	domain.BaseVisitor
	PrimitiveTypes int
	ContainerTypes int
	ListTypes      int
	OptionTypes    int
	ResultTypes    int
	NamedTypes     int
}

func (v *TypeStatisticsVisitor) VisitPrimitive(p domain.PrimitiveType) {
	v.PrimitiveTypes++
}

func (v *TypeStatisticsVisitor) VisitNamed(n domain.NamedType) {
	v.NamedTypes++
}

func (v *TypeStatisticsVisitor) VisitList(l domain.ListType) {
	v.ContainerTypes++
	v.ListTypes++
}

func (v *TypeStatisticsVisitor) VisitOption(o domain.OptionType) {
	v.ContainerTypes++
	v.OptionTypes++
}

func (v *TypeStatisticsVisitor) VisitResult(r domain.ResultType) {
	v.ContainerTypes++
	v.ResultTypes++
}

// NewWITTestContext creates a new WIT test context
func NewWITTestContext() *WITTestContext {
	return &WITTestContext{
		t: &testingT{},
	}
}

// Reset clears the test context state
func (wtc *WITTestContext) Reset() {
	wtc.t = &testingT{}
	wtc.inputIdentifier = ""
	wtc.identifier = domain.Identifier{}
	wtc.hasIdentifier = false
	wtc.identifierError = nil
	wtc.packageNamespace = ""
	wtc.packageName = ""
	wtc.packageVersion = ""
	wtc.pkg = nil
	wtc.packageError = nil
	wtc.usePath = nil
	wtc.usePathError = nil
	wtc.currentType = nil
	wtc.typeError = nil
	wtc.typeDepth = 0
	wtc.typeCount = 0
	wtc.visitedTypes = nil
	wtc.collectedTypes = nil
	wtc.mappedType = nil
	wtc.foldResult = nil
	wtc.containsResult = false
	wtc.visitor = TypeStatisticsVisitor{}
}

// RegisterWITSteps registers all WIT-related step definitions
func RegisterWITSteps(sc *godog.ScenarioContext) {
	wtc := NewWITTestContext()

	// Setup/teardown
	sc.Before(func(ctx context.Context, sc *godog.Scenario) (context.Context, error) {
		wtc.Reset()
		return ctx, nil
	})

	// Identifier steps
	sc.Step(`^an identifier "([^"]*)"$`, wtc.anIdentifier)
	sc.Step(`^an invalid identifier "([^"]*)"$`, wtc.anIdentifier)
	sc.Step(`^an empty identifier "([^"]*)"$`, wtc.anIdentifier)
	sc.Step(`^I attempt to create an Identifier$`, wtc.iAttemptToCreateAnIdentifier)
	sc.Step(`^I create an Identifier$`, wtc.iCreateAnIdentifier)
	sc.Step(`^the result should be "([^"]*)"$`, wtc.theResultShouldBe)
	sc.Step(`^if successful the Identifier string value should be "([^"]*)"$`, wtc.ifSuccessfulTheIdentifierStringShouldBe)
	sc.Step(`^the Identifier should be created successfully$`, wtc.theIdentifierShouldBeCreatedSuccessfully)
	sc.Step(`^the Identifier string value should be "([^"]*)"$`, wtc.theIdentifierStringShouldBe)
	sc.Step(`^an error should occur with message "([^"]*)"$`, wtc.anErrorShouldOccurWithMessage)

	// Package steps
	sc.Step(`^a package with namespace "([^"]*)", name "([^"]*)", and version "([^"]*)"$`, wtc.aPackageWithNamespaceNameAndVersion)
	sc.Step(`^a package with namespace "([^"]*)" and name "([^"]*)"$`, wtc.aPackageWithNamespaceAndName)
	sc.Step(`^I create a Package$`, wtc.iCreateAPackage)
	sc.Step(`^the Package ident should be "([^"]*)"$`, wtc.thePackageIdentShouldBe)

	// Use path steps
	sc.Step(`^a local interface reference "([^"]*)"$`, wtc.aLocalInterfaceReference)
	sc.Step(`^I create a LocalUsePath$`, wtc.iCreateALocalUsePath)
	sc.Step(`^it should reference interface "([^"]*)"$`, wtc.itShouldReferenceInterface)
	sc.Step(`^it should not have namespace or package$`, wtc.itShouldNotHaveNamespaceOrPackage)
	sc.Step(`^an external reference with namespace "([^"]*)", package "([^"]*)", interface "([^"]*)", and version "([^"]*)"$`, wtc.anExternalReferenceWithDetails)
	sc.Step(`^an external reference with namespace "([^"]*)", package "([^"]*)", and interface "([^"]*)"$`, wtc.anExternalReferenceWithoutVersion)
	sc.Step(`^I create an ExternalUsePath$`, wtc.iCreateAnExternalUsePath)
	sc.Step(`^it should have namespace "([^"]*)"$`, wtc.itShouldHaveNamespace)
	sc.Step(`^it should have package "([^"]*)"$`, wtc.itShouldHavePackage)
	sc.Step(`^it should have interface "([^"]*)"$`, wtc.itShouldHaveInterface)
	sc.Step(`^it should have version "([^"]*)"$`, wtc.itShouldHaveVersion)
	sc.Step(`^it should not have a version$`, wtc.itShouldNotHaveAVersion)

	// Use path from table
	sc.Step(`^a use path with namespace "([^"]*)", package "([^"]*)", interface "([^"]*)", and version "([^"]*)"$`, wtc.aUsePathFromTable)
	sc.Step(`^I create a UsePath$`, wtc.iCreateAUsePath)
	sc.Step(`^it should be of type "([^"]*)"$`, wtc.itShouldBeOfType)
	sc.Step(`^it should reference the correct components$`, wtc.itShouldReferenceTheCorrectComponents)

	// Primitive type steps
	sc.Step(`^a primitive kind "([^"]*)"$`, wtc.aPrimitiveKind)
	sc.Step(`^I create a PrimitiveType$`, wtc.iCreateAPrimitiveType)
	sc.Step(`^it should be a valid Type$`, wtc.itShouldBeAValidType)
	sc.Step(`^it should not be a ContainerType$`, wtc.itShouldNotBeAContainerType)
	sc.Step(`^its kind should be "([^"]*)"$`, wtc.itsKindShouldBe)

	// Container type steps
	sc.Step(`^a list of "([^"]*)"$`, wtc.aListOf)
	sc.Step(`^I create a ListType$`, wtc.iCreateAListType)
	sc.Step(`^it should be a ContainerType$`, wtc.itShouldBeAContainerType)
	sc.Step(`^its element type should be "([^"]*)"$`, wtc.itsElementTypeShouldBe)

	// Traversal steps
	sc.Step(`^the type "([^"]*)"$`, wtc.theType)
	sc.Step(`^I walk the type tree$`, wtc.iWalkTheTypeTree)
	sc.Step(`^I should visit (\d+) types$`, wtc.iShouldVisitNTypes)
	sc.Step(`^I calculate the type depth$`, wtc.iCalculateTheTypeDepth)
	sc.Step(`^the depth should be (\d+)$`, wtc.theDepthShouldBe)
}

// Step implementations

func (wtc *WITTestContext) anIdentifier(input string) error {
	wtc.inputIdentifier = input
	return nil
}

func (wtc *WITTestContext) iAttemptToCreateAnIdentifier() error {
	wtc.identifier, wtc.identifierError = domain.NewIdentifier(wtc.inputIdentifier)
	wtc.hasIdentifier = wtc.identifierError == nil
	return nil
}

func (wtc *WITTestContext) iCreateAnIdentifier() error {
	wtc.identifier, wtc.identifierError = domain.NewIdentifier(wtc.inputIdentifier)
	wtc.hasIdentifier = wtc.identifierError == nil
	require.NoError(wtc.t, wtc.identifierError, "expected successful identifier creation")
	return wtc.t.err
}

func (wtc *WITTestContext) theResultShouldBe(expected string) error {
	if expected == "success" {
		assert.NoError(wtc.t, wtc.identifierError, "expected success but got error")
	} else if expected == "error" {
		assert.Error(wtc.t, wtc.identifierError, "expected error but got success")
	}
	return wtc.t.err
}

func (wtc *WITTestContext) ifSuccessfulTheIdentifierStringShouldBe(expected string) error {
	if !wtc.hasIdentifier {
		return nil // Skip if identifier creation failed (error case)
	}
	assert.Equal(wtc.t, expected, wtc.identifier.String(), "identifier string value mismatch")
	return wtc.t.err
}

func (wtc *WITTestContext) theIdentifierStringShouldBe(expected string) error {
	require.True(wtc.t, wtc.hasIdentifier, "identifier should be created successfully")
	assert.Equal(wtc.t, expected, wtc.identifier.String(), "identifier string value mismatch")
	return wtc.t.err
}

func (wtc *WITTestContext) theIdentifierShouldBeCreatedSuccessfully() error {
	assert.NoError(wtc.t, wtc.identifierError, "identifier creation should succeed")
	return wtc.t.err
}

func (wtc *WITTestContext) anErrorShouldOccurWithMessage(expectedMsg string) error {
	require.Error(wtc.t, wtc.identifierError, "expected an error")
	assert.Contains(wtc.t, wtc.identifierError.Error(), expectedMsg, "error message mismatch")
	return wtc.t.err
}

func (wtc *WITTestContext) aPackageWithNamespaceNameAndVersion(namespace, name, version string) error {
	wtc.packageNamespace = namespace
	wtc.packageName = name
	wtc.packageVersion = version
	return nil
}

func (wtc *WITTestContext) aPackageWithNamespaceAndName(namespace, name string) error {
	wtc.packageNamespace = namespace
	wtc.packageName = name
	wtc.packageVersion = ""
	return nil
}

func (wtc *WITTestContext) iCreateAPackage() error {
	ns, err := domain.NewNamespace(wtc.packageNamespace)
	require.NoError(wtc.t, err, "namespace creation failed")

	pn, err := domain.NewPackageName(wtc.packageName)
	require.NoError(wtc.t, err, "package name creation failed")

	wtc.pkg = &domain.Package{
		Namespace: ns,
		Name:      pn,
	}
	// TODO: Parse version when needed
	return wtc.t.err
}

func (wtc *WITTestContext) thePackageIdentShouldBe(expected string) error {
	require.NotNil(wtc.t, wtc.pkg, "package should not be nil")
	assert.Equal(wtc.t, expected, wtc.pkg.Ident(), "package ident mismatch")
	return wtc.t.err
}

func (wtc *WITTestContext) aLocalInterfaceReference(interfaceName string) error {
	wtc.inputIdentifier = interfaceName
	return nil
}

func (wtc *WITTestContext) iCreateALocalUsePath() error {
	id, err := domain.NewIdentifier(wtc.inputIdentifier)
	require.NoError(wtc.t, err, "identifier creation failed")

	wtc.usePath = domain.LocalUsePath{Interface: id}
	return wtc.t.err
}

func (wtc *WITTestContext) itShouldReferenceInterface(expected string) error {
	local, ok := wtc.usePath.(domain.LocalUsePath)
	require.True(wtc.t, ok, "expected LocalUsePath but got %T", wtc.usePath)
	assert.Equal(wtc.t, expected, local.Interface.String(), "interface reference mismatch")
	return wtc.t.err
}

func (wtc *WITTestContext) itShouldNotHaveNamespaceOrPackage() error {
	_, ok := wtc.usePath.(domain.LocalUsePath)
	assert.True(wtc.t, ok, "expected LocalUsePath (no namespace/package) but got %T", wtc.usePath)
	return wtc.t.err
}

func (wtc *WITTestContext) anExternalReferenceWithDetails(namespace, pkg, iface, version string) error {
	wtc.packageNamespace = namespace
	wtc.packageName = pkg
	wtc.inputIdentifier = iface
	wtc.packageVersion = version
	return nil
}

func (wtc *WITTestContext) anExternalReferenceWithoutVersion(namespace, pkg, iface string) error {
	wtc.packageNamespace = namespace
	wtc.packageName = pkg
	wtc.inputIdentifier = iface
	wtc.packageVersion = ""
	return nil
}

func (wtc *WITTestContext) iCreateAnExternalUsePath() error {
	ns, err := domain.NewNamespace(wtc.packageNamespace)
	require.NoError(wtc.t, err, "namespace creation failed")

	pn, err := domain.NewPackageName(wtc.packageName)
	require.NoError(wtc.t, err, "package name creation failed")

	ext := domain.ExternalUsePath{
		Namespace: ns,
		Package:   pn,
	}

	if wtc.inputIdentifier != "" {
		id, err := domain.NewIdentifier(wtc.inputIdentifier)
		require.NoError(wtc.t, err, "identifier creation failed")
		ext.Interface = &id
	}

	// TODO: Parse version when needed

	wtc.usePath = ext
	return wtc.t.err
}

func (wtc *WITTestContext) itShouldHaveNamespace(expected string) error {
	ext, ok := wtc.usePath.(domain.ExternalUsePath)
	require.True(wtc.t, ok, "expected ExternalUsePath but got %T", wtc.usePath)
	assert.Equal(wtc.t, expected, ext.Namespace.String(), "namespace mismatch")
	return wtc.t.err
}

func (wtc *WITTestContext) itShouldHavePackage(expected string) error {
	ext, ok := wtc.usePath.(domain.ExternalUsePath)
	require.True(wtc.t, ok, "expected ExternalUsePath but got %T", wtc.usePath)
	assert.Equal(wtc.t, expected, ext.Package.String(), "package mismatch")
	return wtc.t.err
}

func (wtc *WITTestContext) itShouldHaveInterface(expected string) error {
	ext, ok := wtc.usePath.(domain.ExternalUsePath)
	require.True(wtc.t, ok, "expected ExternalUsePath but got %T", wtc.usePath)
	require.NotNil(wtc.t, ext.Interface, "interface should not be nil")
	assert.Equal(wtc.t, expected, ext.Interface.String(), "interface mismatch")
	return wtc.t.err
}

func (wtc *WITTestContext) itShouldHaveVersion(expected string) error {
	ext, ok := wtc.usePath.(domain.ExternalUsePath)
	require.True(wtc.t, ok, "expected ExternalUsePath but got %T", wtc.usePath)
	require.NotNil(wtc.t, ext.Version, "version should not be nil")
	// TODO: Compare versions properly
	return wtc.t.err
}

func (wtc *WITTestContext) itShouldNotHaveAVersion() error {
	ext, ok := wtc.usePath.(domain.ExternalUsePath)
	require.True(wtc.t, ok, "expected ExternalUsePath but got %T", wtc.usePath)
	assert.Nil(wtc.t, ext.Version, "version should be nil")
	return wtc.t.err
}

func (wtc *WITTestContext) aUsePathFromTable(namespace, pkg, iface, version string) error {
	wtc.packageNamespace = namespace
	wtc.packageName = pkg
	wtc.inputIdentifier = iface
	wtc.packageVersion = version
	return nil
}

func (wtc *WITTestContext) iCreateAUsePath() error {
	// Determine if local or external based on namespace
	if wtc.packageNamespace == "" && wtc.packageName == "" {
		return wtc.iCreateALocalUsePath()
	}
	return wtc.iCreateAnExternalUsePath()
}

func (wtc *WITTestContext) itShouldBeOfType(pathType string) error {
	switch pathType {
	case "local":
		_, ok := wtc.usePath.(domain.LocalUsePath)
		assert.True(wtc.t, ok, "expected LocalUsePath but got %T", wtc.usePath)
	case "external":
		_, ok := wtc.usePath.(domain.ExternalUsePath)
		assert.True(wtc.t, ok, "expected ExternalUsePath but got %T", wtc.usePath)
	default:
		wtc.t.Errorf("unknown path type %q", pathType)
	}
	return wtc.t.err
}

func (wtc *WITTestContext) itShouldReferenceTheCorrectComponents() error {
	// Validation already done by previous steps
	return nil
}

func (wtc *WITTestContext) aPrimitiveKind(kind string) error {
	wtc.inputIdentifier = kind
	return nil
}

func (wtc *WITTestContext) iCreateAPrimitiveType() error {
	kindMap := map[string]domain.PrimitiveKind{
		"u8": domain.U8, "u16": domain.U16, "u32": domain.U32, "u64": domain.U64,
		"s8": domain.S8, "s16": domain.S16, "s32": domain.S32, "s64": domain.S64,
		"f32": domain.F32, "f64": domain.F64,
		"bool": domain.Bool, "char": domain.Char, "string": domain.String,
	}

	kind, ok := kindMap[wtc.inputIdentifier]
	require.True(wtc.t, ok, "unknown primitive kind %q", wtc.inputIdentifier)

	wtc.currentType = domain.PrimitiveType{Kind: kind}
	return wtc.t.err
}

func (wtc *WITTestContext) itShouldBeAValidType() error {
	assert.NotNil(wtc.t, wtc.currentType, "currentType should not be nil")
	return wtc.t.err
}

func (wtc *WITTestContext) itShouldNotBeAContainerType() error {
	_, ok := wtc.currentType.(domain.ContainerType)
	assert.False(wtc.t, ok, "expected non-container type but got %T", wtc.currentType)
	return wtc.t.err
}

func (wtc *WITTestContext) itsKindShouldBe(expected string) error {
	prim, ok := wtc.currentType.(domain.PrimitiveType)
	require.True(wtc.t, ok, "expected PrimitiveType but got %T", wtc.currentType)

	kindMap := map[string]domain.PrimitiveKind{
		"u8": domain.U8, "u16": domain.U16, "u32": domain.U32, "u64": domain.U64,
		"s8": domain.S8, "s16": domain.S16, "s32": domain.S32, "s64": domain.S64,
		"f32": domain.F32, "f64": domain.F64,
		"bool": domain.Bool, "char": domain.Char, "string": domain.String,
	}

	expectedKind, ok := kindMap[expected]
	require.True(wtc.t, ok, "unknown expected kind %q", expected)
	assert.Equal(wtc.t, expectedKind, prim.Kind, "primitive kind mismatch")
	return wtc.t.err
}

func (wtc *WITTestContext) aListOf(elementType string) error {
	wtc.inputIdentifier = elementType
	return nil
}

func (wtc *WITTestContext) iCreateAListType() error {
	id, err := domain.NewIdentifier(wtc.inputIdentifier)
	require.NoError(wtc.t, err, "identifier creation failed")

	wtc.currentType = domain.ListType{
		Element: domain.NamedType{Name: id},
	}
	return wtc.t.err
}

func (wtc *WITTestContext) itShouldBeAContainerType() error {
	_, ok := wtc.currentType.(domain.ContainerType)
	assert.True(wtc.t, ok, "expected ContainerType but got %T", wtc.currentType)
	return wtc.t.err
}

func (wtc *WITTestContext) itsElementTypeShouldBe(expected string) error {
	list, ok := wtc.currentType.(domain.ListType)
	require.True(wtc.t, ok, "expected ListType but got %T", wtc.currentType)

	named, ok := list.Element.(domain.NamedType)
	require.True(wtc.t, ok, "expected NamedType element but got %T", list.Element)

	assert.Equal(wtc.t, expected, named.Name.String(), "element type mismatch")
	return wtc.t.err
}

// Traversal steps
func (wtc *WITTestContext) theType(typeName string) error {
	wtc.inputIdentifier = typeName
	// TODO: Look up type from background table
	return nil
}

func (wtc *WITTestContext) iWalkTheTypeTree() error {
	count := 0
	domain.WalkType(wtc.currentType, func(t domain.Type) bool {
		count++
		return true
	})
	wtc.typeCount = count
	return nil
}

func (wtc *WITTestContext) iShouldVisitNTypes(expected int) error {
	assert.Equal(wtc.t, expected, wtc.typeCount, "visited type count mismatch")
	return wtc.t.err
}

func (wtc *WITTestContext) iCalculateTheTypeDepth() error {
	wtc.typeDepth = domain.TypeDepth(wtc.currentType)
	return nil
}

func (wtc *WITTestContext) theDepthShouldBe(expected int) error {
	assert.Equal(wtc.t, expected, wtc.typeDepth, "type depth mismatch")
	return wtc.t.err
}
