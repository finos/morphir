package pipeline

import (
	"testing"

	"github.com/finos/morphir/pkg/models/ir"
	"github.com/finos/morphir/pkg/pipeline"
	"github.com/finos/morphir/pkg/vfs"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestNewGenStep_ValidatesInput(t *testing.T) {
	step := NewGenStep()
	// VFS can be nil for validation tests
	ctx := pipeline.NewContext("/tmp", 1, pipeline.ModeDefault, nil)

	t.Run("missing output dir", func(t *testing.T) {
		input := GenInput{
			Module:    ir.EmptyModuleDefinition[any, any](),
			OutputDir: vfs.VPath{},
			Options: GenOptions{
				ModulePath: "github.com/example/test",
			},
		}

		_, result := step.Execute(ctx, input)

		assert.Error(t, result.Err)
		require.NotEmpty(t, result.Diagnostics)
		assert.Equal(t, pipeline.SeverityError, result.Diagnostics[0].Severity)
		assert.Contains(t, result.Diagnostics[0].Message, "output directory is required")
	})

	t.Run("missing module path", func(t *testing.T) {
		outputDir := vfs.MustVPath("/output")
		input := GenInput{
			Module:    ir.EmptyModuleDefinition[any, any](),
			OutputDir: outputDir,
			Options: GenOptions{
				ModulePath: "",
			},
		}

		_, result := step.Execute(ctx, input)

		assert.Error(t, result.Err)
		require.NotEmpty(t, result.Diagnostics)
		assert.Equal(t, pipeline.SeverityError, result.Diagnostics[0].Severity)
		assert.Contains(t, result.Diagnostics[0].Message, "module path is required")
	})
}

func TestNewGenStep_GeneratesFiles(t *testing.T) {
	step := NewGenStep()
	ctx := pipeline.NewContext("/tmp", 1, pipeline.ModeDefault, nil)

	outputDir := vfs.MustVPath("/output")
	input := GenInput{
		Module:    ir.EmptyModuleDefinition[any, any](),
		OutputDir: outputDir,
		Options: GenOptions{
			ModulePath: "github.com/example/test",
			Workspace:  false,
		},
	}

	output, result := step.Execute(ctx, input)

	assert.NoError(t, result.Err)
	assert.NotEmpty(t, output.GeneratedFiles)

	// Should generate go.mod
	goMod, hasGoMod := output.GeneratedFiles["go.mod"]
	assert.True(t, hasGoMod, "should generate go.mod")
	assert.Contains(t, goMod, "module github.com/example/test")
	assert.Contains(t, goMod, "go 1.25")

	// Should generate source file
	sourceFile, hasSource := output.GeneratedFiles["generated/generated.go"]
	assert.True(t, hasSource, "should generate source file")
	assert.Contains(t, sourceFile, "package generated")

	// Should have artifacts
	assert.NotEmpty(t, result.Artifacts)
	assert.NotEmpty(t, output.ModuleFiles)
}

func TestNewGenStep_WorkspaceMode(t *testing.T) {
	step := NewGenStep()
	ctx := pipeline.NewContext("/tmp", 1, pipeline.ModeDefault, nil)

	outputDir := vfs.MustVPath("/output")
	input := GenInput{
		Module:    ir.EmptyModuleDefinition[any, any](),
		OutputDir: outputDir,
		Options: GenOptions{
			ModulePath: "github.com/example/test",
			Workspace:  true,
		},
	}

	output, result := step.Execute(ctx, input)

	assert.NoError(t, result.Err)

	// Should generate go.work in workspace mode
	goWork, hasGoWork := output.GeneratedFiles["go.work"]
	assert.True(t, hasGoWork, "should generate go.work in workspace mode")
	assert.Contains(t, goWork, "go 1.25")
	assert.Contains(t, goWork, "use (")

	// Should have workspace file artifact
	assert.NotNil(t, output.WorkspaceFile)
}

func TestNewGenStep_WithTypeAlias(t *testing.T) {
	step := NewGenStep()
	ctx := pipeline.NewContext("/tmp", 1, pipeline.ModeDefault, nil)

	// Create a simple type alias module
	userIDName := ir.NameFromString("UserID")
	stringType := ir.NewTypeReference[any](
		nil,
		ir.FQNameFromParts(
			ir.PathFromParts([]ir.Name{ir.NameFromString("morphir"), ir.NameFromString("sdk")}),
			ir.PathFromParts([]ir.Name{ir.NameFromString("basics")}),
			ir.NameFromString("String"),
		),
		nil,
	)

	typeAlias := ir.NewTypeAliasDefinition[any](nil, stringType)
	documented := ir.NewDocumented("UserID is a unique identifier", typeAlias)
	accessControlled := ir.Public(documented)
	moduleType := ir.ModuleDefinitionTypeFromParts[any](userIDName, accessControlled)

	module := ir.NewModuleDefinition[any, any](
		[]ir.ModuleDefinitionType[any]{moduleType},
		nil,
		nil,
	)

	outputDir := vfs.MustVPath("/output")
	input := GenInput{
		Module:    module,
		OutputDir: outputDir,
		Options: GenOptions{
			ModulePath: "github.com/example/test",
		},
	}

	output, result := step.Execute(ctx, input)

	assert.NoError(t, result.Err)

	// Should generate source with type alias
	// String type from Morphir SDK maps to Go's native string type
	sourceFile, hasSource := output.GeneratedFiles["generated/generated.go"]
	assert.True(t, hasSource, "should generate source file")
	assert.Contains(t, sourceFile, "type UserID")
	assert.Contains(t, sourceFile, "= string")
}
