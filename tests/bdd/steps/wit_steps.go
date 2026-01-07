package steps

import (
	"context"
	"fmt"
	"path/filepath"
	"strings"

	"github.com/cucumber/godog"
	"github.com/finos/morphir/pkg/bindings/wit"
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

	// WASI package parsing
	wasiPackageID     string
	parsedPackages    []domain.Package
	parseError        error
	currentInterface  *domain.Interface
	parseWarnings     []string

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
	wtc.wasiPackageID = ""
	wtc.parsedPackages = nil
	wtc.parseError = nil
	wtc.currentInterface = nil
	wtc.parseWarnings = nil
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

	// WASI package parsing steps
	sc.Step(`^the WASI package "([^"]*)"$`, wtc.theWASIPackage)
	sc.Step(`^I parse the package$`, wtc.iParseThePackage)
	sc.Step(`^it should contain an interface "([^"]*)"$`, wtc.itShouldContainAnInterface)
	sc.Step(`^the interface should have the following types:$`, wtc.theInterfaceShouldHaveTheFollowingTypes)
	sc.Step(`^the interface should have the following functions:$`, wtc.theInterfaceShouldHaveTheFollowingFunctions)
	sc.Step(`^the interface should have the following type aliases:$`, wtc.theInterfaceShouldHaveTheFollowingTypeAliases)
	sc.Step(`^the package namespace should be "([^"]*)"$`, wtc.thePackageNamespaceShouldBe)
	sc.Step(`^the package name should be "([^"]*)"$`, wtc.thePackageNameShouldBe)
	sc.Step(`^the package version should be "([^"]*)"$`, wtc.thePackageVersionShouldBe)
	sc.Step(`^it should have at least (\d+) interfaces$`, wtc.itShouldHaveAtLeastNInterfaces)
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

// ====================
// WASI Package Parsing Steps
// ====================

// theWASIPackage sets up a WASI package to be parsed
func (wtc *WITTestContext) theWASIPackage(packageID string) error {
	wtc.wasiPackageID = packageID
	return nil
}

// iParse ThePackage parses the WIT package
func (wtc *WITTestContext) iParseThePackage() error {
	// Map package ID to fixture path
	// e.g., "wasi:clocks@0.2.0" -> "wit/wasi/clocks.wit"
	fixturePath, err := wtc.resolveWASIFixturePath(wtc.wasiPackageID)
	if err != nil {
		wtc.parseError = err
		return nil
	}

	// Load and parse the WIT file
	packages, warnings, parseErr := wit.LoadAndParseWIT(fixturePath)
	wtc.parsedPackages = packages
	wtc.parseWarnings = warnings
	wtc.parseError = parseErr
	return nil
}

// resolveWASIFixturePath converts a package ID to a fixture file path
func (wtc *WITTestContext) resolveWASIFixturePath(packageID string) (string, error) {
	// Parse package ID: "wasi:clocks@0.2.0" -> namespace=wasi, name=clocks
	parts := strings.Split(packageID, ":")
	if len(parts) != 2 {
		return "", fmt.Errorf("invalid package ID format: %s", packageID)
	}

	namespace := parts[0]
	nameAndVersion := parts[1]

	// Extract package name (before @)
	nameParts := strings.Split(nameAndVersion, "@")
	name := nameParts[0]

	// Build fixture path
	// We currently only have fixtures in tests/bdd/testdata/wit/wasi/
	if namespace != "wasi" {
		return "", fmt.Errorf("only wasi packages are currently supported in fixtures")
	}

	// The fixture path is relative to the test binary
	// Use filepath.Join to build the path
	return filepath.Join("..", "..", "..", "..", "..", "tests", "bdd", "testdata", "wit", namespace, name+".wit"), nil
}

// itShouldContainAnInterface verifies the package contains a specific interface
func (wtc *WITTestContext) itShouldContainAnInterface(interfaceName string) error {
	require.NoError(wtc.t, wtc.parseError, "parse should have succeeded")
	require.NotEmpty(wtc.t, wtc.parsedPackages, "should have parsed packages")

	pkg := wtc.parsedPackages[0]
	for _, iface := range pkg.Interfaces {
		if iface.Name.String() == interfaceName {
			wtc.currentInterface = &iface
			return wtc.t.err
		}
	}

	assert.Fail(wtc.t, fmt.Sprintf("interface %s not found in package", interfaceName))
	return wtc.t.err
}

// theInterfaceShouldHaveTheFollowingTypes verifies interface types from a table
func (wtc *WITTestContext) theInterfaceShouldHaveTheFollowingTypes(table *godog.Table) error {
	require.NotNil(wtc.t, wtc.currentInterface, "current interface should be set")

	for i, row := range table.Rows {
		if i == 0 {
			// Skip header row
			continue
		}

		typeName := row.Cells[0].Value
		expectedKind := row.Cells[1].Value

		// Find the type in the interface
		found := false
		for _, typeDef := range wtc.currentInterface.Types {
			if typeDef.Name.String() == typeName {
				found = true
				// Check the kind
				actualKind := getTypeDefKindName(typeDef.Kind)
				assert.Equal(wtc.t, expectedKind, actualKind,
					fmt.Sprintf("type %s should be %s but got %s", typeName, expectedKind, actualKind))
				break
			}
		}

		if !found {
			assert.Fail(wtc.t, fmt.Sprintf("type %s not found in interface", typeName))
		}
	}

	return wtc.t.err
}

// getTypeDefKindName returns the string name of a TypeDefKind
func getTypeDefKindName(kind domain.TypeDefKind) string {
	switch kind.(type) {
	case domain.RecordDef:
		return "record"
	case domain.VariantDef:
		return "variant"
	case domain.EnumDef:
		return "enum"
	case domain.FlagsDef:
		return "flags"
	case domain.ResourceDef:
		return "resource"
	case domain.TypeAliasDef:
		return "alias"
	default:
		return "unknown"
	}
}

// primitiveKindToString converts a PrimitiveKind to its string representation
func primitiveKindToString(kind domain.PrimitiveKind) string {
	switch kind {
	case domain.U8:
		return "u8"
	case domain.U16:
		return "u16"
	case domain.U32:
		return "u32"
	case domain.U64:
		return "u64"
	case domain.S8:
		return "s8"
	case domain.S16:
		return "s16"
	case domain.S32:
		return "s32"
	case domain.S64:
		return "s64"
	case domain.F32:
		return "f32"
	case domain.F64:
		return "f64"
	case domain.Bool:
		return "bool"
	case domain.Char:
		return "char"
	case domain.String:
		return "string"
	default:
		return "unknown"
	}
}

// theInterfaceShouldHaveTheFollowingFunctions verifies interface functions from a table
func (wtc *WITTestContext) theInterfaceShouldHaveTheFollowingFunctions(table *godog.Table) error {
	require.NotNil(wtc.t, wtc.currentInterface, "current interface should be set")

	for i, row := range table.Rows {
		if i == 0 {
			// Skip header row
			continue
		}

		funcName := row.Cells[0].Value
		// params := row.Cells[1].Value  // TODO: Verify params
		returns := row.Cells[2].Value

		// Find the function in the interface
		found := false
		for _, fn := range wtc.currentInterface.Functions {
			if fn.Name.String() == funcName {
				found = true
				// Verify return type
				if returns != "" {
					require.NotEmpty(wtc.t, fn.Results, "function should have results")
					// For now, just check that results exist
					// TODO: More detailed verification of return types
				}
				break
			}
		}

		if !found {
			assert.Fail(wtc.t, fmt.Sprintf("function %s not found in interface", funcName))
		}
	}

	return wtc.t.err
}

// theInterfaceShouldHaveTheFollowingTypeAliases verifies type aliases from a table
func (wtc *WITTestContext) theInterfaceShouldHaveTheFollowingTypeAliases(table *godog.Table) error {
	require.NotNil(wtc.t, wtc.currentInterface, "current interface should be set")

	for i, row := range table.Rows {
		if i == 0 {
			// Skip header row
			continue
		}

		aliasName := row.Cells[0].Value
		expectedTarget := row.Cells[1].Value

		// Find the type alias in the interface
		found := false
		for _, typeDef := range wtc.currentInterface.Types {
			if typeDef.Name.String() == aliasName {
				found = true
				// Check if it's a type alias
				alias, ok := typeDef.Kind.(domain.TypeAliasDef)
				if !ok {
					assert.Fail(wtc.t, fmt.Sprintf("type %s is not an alias", aliasName))
					continue
				}

				// Verify target type
				// For primitives, check the primitive kind
				if prim, ok := alias.Target.(domain.PrimitiveType); ok {
					actualTarget := primitiveKindToString(prim.Kind)
					assert.Equal(wtc.t, expectedTarget, actualTarget,
						fmt.Sprintf("alias %s target mismatch", aliasName))
				}
				break
			}
		}

		if !found {
			assert.Fail(wtc.t, fmt.Sprintf("type alias %s not found in interface", aliasName))
		}
	}

	return wtc.t.err
}

// thePackageNamespaceShouldBe verifies the package namespace
func (wtc *WITTestContext) thePackageNamespaceShouldBe(expected string) error {
	require.NoError(wtc.t, wtc.parseError, "parse should have succeeded")
	require.NotEmpty(wtc.t, wtc.parsedPackages, "should have parsed packages")

	pkg := wtc.parsedPackages[0]
	assert.Equal(wtc.t, expected, pkg.Namespace.String(), "package namespace mismatch")
	return wtc.t.err
}

// thePackageNameShouldBe verifies the package name
func (wtc *WITTestContext) thePackageNameShouldBe(expected string) error {
	require.NoError(wtc.t, wtc.parseError, "parse should have succeeded")
	require.NotEmpty(wtc.t, wtc.parsedPackages, "should have parsed packages")

	pkg := wtc.parsedPackages[0]
	assert.Equal(wtc.t, expected, pkg.Name.String(), "package name mismatch")
	return wtc.t.err
}

// thePackageVersionShouldBe verifies the package version
func (wtc *WITTestContext) thePackageVersionShouldBe(expected string) error {
	require.NoError(wtc.t, wtc.parseError, "parse should have succeeded")
	require.NotEmpty(wtc.t, wtc.parsedPackages, "should have parsed packages")

	pkg := wtc.parsedPackages[0]
	if pkg.Version != nil {
		assert.Equal(wtc.t, expected, pkg.Version.String(), "package version mismatch")
	} else {
		assert.Fail(wtc.t, "package has no version")
	}
	return wtc.t.err
}

// itShouldHaveAtLeastNInterfaces verifies minimum interface count
func (wtc *WITTestContext) itShouldHaveAtLeastNInterfaces(minCount int) error {
	require.NoError(wtc.t, wtc.parseError, "parse should have succeeded")
	require.NotEmpty(wtc.t, wtc.parsedPackages, "should have parsed packages")

	pkg := wtc.parsedPackages[0]
	assert.GreaterOrEqual(wtc.t, len(pkg.Interfaces), minCount,
		fmt.Sprintf("package should have at least %d interfaces", minCount))
	return wtc.t.err
}
