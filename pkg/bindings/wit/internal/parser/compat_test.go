package parser

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/finos/morphir/pkg/bindings/wit/domain"
	"github.com/finos/morphir/pkg/bindings/wit/internal/adapter"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"go.bytecodealliance.org/wit"
)

// TestCompatibilityWithBytecodealliance compares our pure parser output
// with the bytecodealliance parser output for the same WIT files.
func TestCompatibilityWithBytecodealliance(t *testing.T) {
	// Find WASI test fixtures
	fixturesDir := filepath.Join("..", "..", "..", "..", "..", "tests", "bdd", "testdata", "wit", "wasi")
	entries, err := os.ReadDir(fixturesDir)
	if err != nil {
		t.Skipf("Could not read fixtures directory: %v", err)
	}

	for _, entry := range entries {
		if !entry.IsDir() && filepath.Ext(entry.Name()) == ".wit" {
			t.Run(entry.Name(), func(t *testing.T) {
				testFile := filepath.Join(fixturesDir, entry.Name())
				compareParserOutputs(t, testFile)
			})
		}
	}
}

// compareParserOutputs parses a WIT file with both parsers and compares the results.
func compareParserOutputs(t *testing.T, filename string) {
	// Read the file
	content, err := os.ReadFile(filename)
	require.NoError(t, err, "failed to read test file")

	// Parse with our pure parser
	ourParser := NewParser(string(content))
	ourPkg, ourErr := ourParser.Parse()

	// Parse with bytecodealliance
	witResolve, witErr := wit.LoadWIT(filename)

	// Both should succeed or fail
	if witErr != nil {
		// bytecodealliance failed, we may or may not fail
		t.Logf("bytecodealliance failed: %v", witErr)
		return
	}

	require.NoError(t, ourErr, "our parser failed where bytecodealliance succeeded")

	// Convert bytecodealliance output to our domain model
	witPkgs, _, err := adapter.FromWIT(witResolve)
	require.NoError(t, err, "adapter failed")
	require.Len(t, witPkgs, 1, "expected exactly one package from bytecodealliance")

	witPkg := witPkgs[0]

	// Compare package metadata
	t.Run("package_metadata", func(t *testing.T) {
		assert.Equal(t, witPkg.Namespace.String(), ourPkg.Namespace.String(), "namespace mismatch")
		assert.Equal(t, witPkg.Name.String(), ourPkg.Name.String(), "package name mismatch")
		if witPkg.Version != nil && ourPkg.Version != nil {
			assert.Equal(t, witPkg.Version.String(), ourPkg.Version.String(), "version mismatch")
		}
	})

	// Compare interfaces
	t.Run("interfaces", func(t *testing.T) {
		assert.Equal(t, len(witPkg.Interfaces), len(ourPkg.Interfaces), "interface count mismatch")

		// Build maps for comparison
		witIfaces := make(map[string]domain.Interface)
		for _, iface := range witPkg.Interfaces {
			witIfaces[iface.Name.String()] = iface
		}

		for _, ourIface := range ourPkg.Interfaces {
			witIface, exists := witIfaces[ourIface.Name.String()]
			if !exists {
				t.Errorf("interface %s exists in our output but not in bytecodealliance", ourIface.Name.String())
				continue
			}

			compareInterfaces(t, ourIface.Name.String(), witIface, ourIface)
		}
	})

	// Compare worlds
	t.Run("worlds", func(t *testing.T) {
		assert.Equal(t, len(witPkg.Worlds), len(ourPkg.Worlds), "world count mismatch")

		for i, ourWorld := range ourPkg.Worlds {
			if i < len(witPkg.Worlds) {
				witWorld := witPkg.Worlds[i]
				assert.Equal(t, witWorld.Name.String(), ourWorld.Name.String(), "world name mismatch")
			}
		}
	})
}

// compareInterfaces compares two interfaces in detail.
func compareInterfaces(t *testing.T, name string, wit, our domain.Interface) {
	// Check if interface has resources - bytecodealliance stores resource methods
	// as interface functions, while our parser stores them in ResourceDef
	hasResources := false
	for _, td := range our.Types {
		if _, ok := td.Kind.(domain.ResourceDef); ok {
			hasResources = true
			break
		}
	}

	// Compare type definitions
	t.Run(name+"/types", func(t *testing.T) {
		if hasResources {
			// When resources are involved, bytecodealliance may create additional type
			// definitions for handle types (own<T>, borrow<T>), so we only check that
			// our types are a subset
			witTypes := make(map[string]domain.TypeDef)
			for _, td := range wit.Types {
				witTypes[td.Name.String()] = td
			}

			for _, ourTd := range our.Types {
				if witTd, exists := witTypes[ourTd.Name.String()]; exists {
					compareTypeDefs(t, ourTd.Name.String(), witTd, ourTd)
				}
				// Allow our parser to have types that bytecodealliance doesn't
				// This is because we may store types inline while bytecodealliance
				// hoists them to interface level
			}
		} else {
			assert.Equal(t, len(wit.Types), len(our.Types), "type count mismatch for interface %s", name)

			witTypes := make(map[string]domain.TypeDef)
			for _, td := range wit.Types {
				witTypes[td.Name.String()] = td
			}

			for _, ourTd := range our.Types {
				witTd, exists := witTypes[ourTd.Name.String()]
				if !exists {
					t.Errorf("type %s exists in our output but not in bytecodealliance", ourTd.Name.String())
					continue
				}

				compareTypeDefs(t, ourTd.Name.String(), witTd, ourTd)
			}
		}
	})

	// Compare functions
	t.Run(name+"/functions", func(t *testing.T) {
		if hasResources {
			// KNOWN DIFFERENCE: bytecodealliance stores resource methods as interface
			// functions, while our parser stores them in ResourceDef.Methods.
			// We only compare standalone functions (not resource methods).
			t.Logf("Interface %s has resources - skipping function count comparison (known architectural difference)", name)

			// Compare only the functions that exist in both
			witFuncs := make(map[string]domain.Function)
			for _, fn := range wit.Functions {
				witFuncs[fn.Name.String()] = fn
			}

			for _, ourFn := range our.Functions {
				if witFn, exists := witFuncs[ourFn.Name.String()]; exists {
					compareFunctions(t, ourFn.Name.String(), witFn, ourFn)
				}
			}
		} else {
			assert.Equal(t, len(wit.Functions), len(our.Functions), "function count mismatch for interface %s", name)

			witFuncs := make(map[string]domain.Function)
			for _, fn := range wit.Functions {
				witFuncs[fn.Name.String()] = fn
			}

			for _, ourFn := range our.Functions {
				witFn, exists := witFuncs[ourFn.Name.String()]
				if !exists {
					t.Errorf("function %s exists in our output but not in bytecodealliance", ourFn.Name.String())
					continue
				}

				compareFunctions(t, ourFn.Name.String(), witFn, ourFn)
			}
		}
	})
}

// compareTypeDefs compares two type definitions.
func compareTypeDefs(t *testing.T, name string, wit, our domain.TypeDef) {
	assert.Equal(t, wit.Name.String(), our.Name.String(), "type name mismatch")

	// Compare kind types
	switch witKind := wit.Kind.(type) {
	case domain.RecordDef:
		ourKind, ok := our.Kind.(domain.RecordDef)
		if !ok {
			t.Errorf("type %s: expected RecordDef, got %T", name, our.Kind)
			return
		}
		assert.Equal(t, len(witKind.Fields), len(ourKind.Fields), "field count mismatch for record %s", name)
		for i, witField := range witKind.Fields {
			if i < len(ourKind.Fields) {
				assert.Equal(t, witField.Name.String(), ourKind.Fields[i].Name.String(), "field name mismatch")
				compareTypes(t, name+"."+witField.Name.String(), witField.Type, ourKind.Fields[i].Type)
			}
		}

	case domain.EnumDef:
		ourKind, ok := our.Kind.(domain.EnumDef)
		if !ok {
			t.Errorf("type %s: expected EnumDef, got %T", name, our.Kind)
			return
		}
		assert.Equal(t, len(witKind.Cases), len(ourKind.Cases), "case count mismatch for enum %s", name)
		for i, witCase := range witKind.Cases {
			if i < len(ourKind.Cases) {
				assert.Equal(t, witCase.String(), ourKind.Cases[i].String(), "enum case mismatch")
			}
		}

	case domain.VariantDef:
		ourKind, ok := our.Kind.(domain.VariantDef)
		if !ok {
			t.Errorf("type %s: expected VariantDef, got %T", name, our.Kind)
			return
		}
		assert.Equal(t, len(witKind.Cases), len(ourKind.Cases), "case count mismatch for variant %s", name)

	case domain.FlagsDef:
		ourKind, ok := our.Kind.(domain.FlagsDef)
		if !ok {
			t.Errorf("type %s: expected FlagsDef, got %T", name, our.Kind)
			return
		}
		assert.Equal(t, len(witKind.Flags), len(ourKind.Flags), "flag count mismatch for flags %s", name)

	case domain.TypeAliasDef:
		ourKind, ok := our.Kind.(domain.TypeAliasDef)
		if !ok {
			t.Errorf("type %s: expected TypeAliasDef, got %T", name, our.Kind)
			return
		}
		compareTypes(t, name, witKind.Target, ourKind.Target)

	case domain.ResourceDef:
		_, ok := our.Kind.(domain.ResourceDef)
		if !ok {
			t.Errorf("type %s: expected ResourceDef, got %T", name, our.Kind)
			return
		}
		// Resource comparison is complex due to methods, skip detailed comparison for now
	}
}

// compareFunctions compares two functions.
func compareFunctions(t *testing.T, name string, wit, our domain.Function) {
	assert.Equal(t, wit.Name.String(), our.Name.String(), "function name mismatch")
	assert.Equal(t, len(wit.Params), len(our.Params), "param count mismatch for function %s", name)
	assert.Equal(t, len(wit.Results), len(our.Results), "result count mismatch for function %s", name)

	// Compare parameters
	for i, witParam := range wit.Params {
		if i < len(our.Params) {
			assert.Equal(t, witParam.Name.String(), our.Params[i].Name.String(), "param name mismatch")
			compareTypes(t, name+".param."+witParam.Name.String(), witParam.Type, our.Params[i].Type)
		}
	}

	// Compare results
	for i, witResult := range wit.Results {
		if i < len(our.Results) {
			compareTypes(t, name+".result", witResult, our.Results[i])
		}
	}
}

// compareTypes compares two types.
func compareTypes(t *testing.T, context string, wit, our domain.Type) {
	if wit == nil && our == nil {
		return
	}
	if wit == nil || our == nil {
		t.Errorf("%s: type nil mismatch (wit=%v, our=%v)", context, wit, our)
		return
	}

	switch witType := wit.(type) {
	case domain.PrimitiveType:
		ourType, ok := our.(domain.PrimitiveType)
		if !ok {
			t.Errorf("%s: expected PrimitiveType, got %T", context, our)
			return
		}
		assert.Equal(t, witType.Kind, ourType.Kind, "primitive kind mismatch at %s", context)

	case domain.NamedType:
		ourType, ok := our.(domain.NamedType)
		if !ok {
			t.Errorf("%s: expected NamedType, got %T", context, our)
			return
		}
		assert.Equal(t, witType.Name.String(), ourType.Name.String(), "named type mismatch at %s", context)

	case domain.ListType:
		ourType, ok := our.(domain.ListType)
		if !ok {
			t.Errorf("%s: expected ListType, got %T", context, our)
			return
		}
		compareTypes(t, context+".element", witType.Element, ourType.Element)

	case domain.OptionType:
		ourType, ok := our.(domain.OptionType)
		if !ok {
			t.Errorf("%s: expected OptionType, got %T", context, our)
			return
		}
		compareTypes(t, context+".inner", witType.Inner, ourType.Inner)

	case domain.ResultType:
		ourType, ok := our.(domain.ResultType)
		if !ok {
			t.Errorf("%s: expected ResultType, got %T", context, our)
			return
		}
		if witType.Ok != nil && ourType.Ok != nil {
			compareTypes(t, context+".ok", *witType.Ok, *ourType.Ok)
		}
		if witType.Err != nil && ourType.Err != nil {
			compareTypes(t, context+".err", *witType.Err, *ourType.Err)
		}

	case domain.TupleType:
		ourType, ok := our.(domain.TupleType)
		if !ok {
			t.Errorf("%s: expected TupleType, got %T", context, our)
			return
		}
		assert.Equal(t, len(witType.Types), len(ourType.Types), "tuple length mismatch at %s", context)

	case domain.HandleType:
		ourType, ok := our.(domain.HandleType)
		if !ok {
			t.Errorf("%s: expected HandleType, got %T", context, our)
			return
		}
		assert.Equal(t, witType.Resource.String(), ourType.Resource.String(), "handle resource mismatch at %s", context)
		assert.Equal(t, witType.IsBorrow, ourType.IsBorrow, "handle borrow flag mismatch at %s", context)
	}
}

// TestParseWASIFixtures tests that our parser can parse all WASI fixture files.
func TestParseWASIFixtures(t *testing.T) {
	fixturesDir := filepath.Join("..", "..", "..", "..", "..", "tests", "bdd", "testdata", "wit", "wasi")
	entries, err := os.ReadDir(fixturesDir)
	if err != nil {
		t.Skipf("Could not read fixtures directory: %v", err)
	}

	for _, entry := range entries {
		if !entry.IsDir() && filepath.Ext(entry.Name()) == ".wit" {
			t.Run(entry.Name(), func(t *testing.T) {
				testFile := filepath.Join(fixturesDir, entry.Name())
				content, err := os.ReadFile(testFile)
				require.NoError(t, err)

				parser := NewParser(string(content))
				pkg, err := parser.Parse()
				require.NoError(t, err, "failed to parse %s", entry.Name())

				// Basic validation
				assert.NotEmpty(t, pkg.Namespace.String(), "namespace should not be empty")
				assert.NotEmpty(t, pkg.Name.String(), "package name should not be empty")
				t.Logf("Parsed %s: %s:%s@%v with %d interfaces, %d worlds",
					entry.Name(),
					pkg.Namespace.String(),
					pkg.Name.String(),
					pkg.Version,
					len(pkg.Interfaces),
					len(pkg.Worlds))
			})
		}
	}
}
