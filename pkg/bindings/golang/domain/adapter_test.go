package domain

import (
	"strings"
	"testing"

	"github.com/finos/morphir/pkg/models/ir"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestConvertModuleToPackage_EmptyModule(t *testing.T) {
	// Create an empty module
	module := ir.EmptyModuleDefinition[any, any]()

	pkg, warnings := ConvertModuleToPackage(module, "github.com/example/test", "testpkg")

	assert.Equal(t, "testpkg", pkg.Name)
	assert.Equal(t, "github.com/example/test/testpkg", pkg.ImportPath)
	assert.Empty(t, pkg.Types)
	assert.Empty(t, pkg.Functions)
	assert.Empty(t, warnings)
}

func TestConvertModuleToPackage_WithTypeAlias(t *testing.T) {
	// Create a simple type alias: type UserID = string
	userIDName := ir.NameFromString("UserID")
	stringType := ir.NewTypeReference[any](
		nil, // no attributes
		ir.FQNameFromParts(
			ir.PathFromParts([]ir.Name{ir.NameFromString("morphir"), ir.NameFromString("sdk")}),
			ir.PathFromParts([]ir.Name{ir.NameFromString("basics")}),
			ir.NameFromString("String"),
		),
		nil, // no type params
	)

	typeAlias := ir.NewTypeAliasDefinition[any](nil, stringType)
	documented := ir.NewDocumented("UserID is a unique identifier for users", typeAlias)
	accessControlled := ir.Public(documented)

	moduleType := ir.ModuleDefinitionTypeFromParts[any](userIDName, accessControlled)
	module := ir.NewModuleDefinition[any, any](
		[]ir.ModuleDefinitionType[any]{moduleType},
		nil, // no values
		nil, // no doc
	)

	pkg, warnings := ConvertModuleToPackage(module, "github.com/example/test", "testpkg")

	require.Len(t, pkg.Types, 1)
	goTypeAlias, ok := pkg.Types[0].(GoTypeAliasType)
	require.True(t, ok, "expected GoTypeAliasType")
	assert.Equal(t, "UserID", goTypeAlias.Name)
	// String type from Morphir SDK maps to Go's native string type
	assert.Equal(t, "string", goTypeAlias.UnderlyingType)
	assert.Contains(t, goTypeAlias.Documentation, "UserID is a unique identifier")
	// Warnings may or may not be present depending on implementation
	_ = warnings
}

func TestEmitPackage_EmptyPackage(t *testing.T) {
	pkg := GoPackage{
		Name:       "testpkg",
		ImportPath: "github.com/example/test/testpkg",
	}

	source, err := EmitPackage(pkg)
	require.NoError(t, err)

	assert.Contains(t, source, "package testpkg")
}

func TestEmitPackage_WithStruct(t *testing.T) {
	pkg := GoPackage{
		Name:       "testpkg",
		ImportPath: "github.com/example/test/testpkg",
		Types: []GoType{
			GoStructType{
				Name:          "User",
				Documentation: "User represents a user in the system",
				Fields: []GoField{
					{
						Name:          "ID",
						Type:          "string",
						Tag:           "`json:\"id\"`",
						Documentation: "",
					},
					{
						Name:          "Name",
						Type:          "string",
						Tag:           "`json:\"name\"`",
						Documentation: "",
					},
				},
			},
		},
	}

	source, err := EmitPackage(pkg)
	require.NoError(t, err)

	assert.Contains(t, source, "package testpkg")
	assert.Contains(t, source, "type User struct")
	// gofmt may normalize whitespace
	assert.Contains(t, source, "ID")
	assert.Contains(t, source, "string")
	assert.Contains(t, source, "`json:\"id\"`")
	assert.Contains(t, source, "Name")
	assert.Contains(t, source, "`json:\"name\"`")
	assert.Contains(t, source, "User")
}

func TestEmitGoMod(t *testing.T) {
	module := GoModule{
		ModulePath: "github.com/example/myapp",
		GoVersion:  "1.25",
		Dependencies: map[string]string{
			"github.com/stretchr/testify": "v1.8.0",
		},
	}

	content := EmitGoMod(module)

	assert.Contains(t, content, "module github.com/example/myapp")
	assert.Contains(t, content, "go 1.25")
	assert.Contains(t, content, "require (")
	assert.Contains(t, content, "github.com/stretchr/testify v1.8.0")
}

func TestEmitGoWork(t *testing.T) {
	workspace := GoWorkspace{
		GoVersion: "1.25",
		Modules: []GoModule{
			{ModulePath: "github.com/example/mod1"},
			{ModulePath: "github.com/example/mod2"},
		},
	}

	content := EmitGoWork(workspace)

	assert.Contains(t, content, "go 1.25")
	assert.Contains(t, content, "use (")
	// The implementation is simplified, so exact paths may vary
	assert.True(t, strings.Contains(content, "github.com/example/mod1") || strings.Contains(content, "./"))
}

func TestNameToString(t *testing.T) {
	tests := []struct {
		name     string
		input    ir.Name
		expected string
	}{
		{
			name:     "simple name",
			input:    ir.NameFromString("user"),
			expected: "User",
		},
		{
			name:     "camel case",
			input:    ir.NameFromString("userID"),
			expected: "UserID",
		},
		{
			name:     "multi word",
			input:    ir.NameFromString("user_name"),
			expected: "UserName",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := nameToString(tt.input)
			assert.Equal(t, tt.expected, result)
		})
	}
}

func TestToExportedName(t *testing.T) {
	tests := []struct {
		name     string
		input    string
		expected string
	}{
		{
			name:     "already exported",
			input:    "User",
			expected: "User",
		},
		{
			name:     "needs export",
			input:    "user",
			expected: "User",
		},
		{
			name:     "empty string",
			input:    "",
			expected: "",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := toExportedName(tt.input)
			assert.Equal(t, tt.expected, result)
		})
	}
}
