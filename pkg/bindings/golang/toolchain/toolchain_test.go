package toolchain

import (
	"testing"

	"github.com/finos/morphir/pkg/models/ir"
	"github.com/finos/morphir/pkg/pipeline"
	"github.com/finos/morphir/pkg/toolchain"
	"github.com/finos/morphir/pkg/vfs"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestGolangToolchain(t *testing.T) {
	tc := GolangToolchain()

	t.Run("has correct name", func(t *testing.T) {
		assert.Equal(t, "golang", tc.Name)
	})

	t.Run("is native type", func(t *testing.T) {
		assert.Equal(t, toolchain.ToolchainTypeNative, tc.Type)
	})

	t.Run("has three tasks", func(t *testing.T) {
		assert.Len(t, tc.Tasks, 3)

		taskNames := make([]string, len(tc.Tasks))
		for i, task := range tc.Tasks {
			taskNames[i] = task.Name
		}
		assert.Contains(t, taskNames, "make")
		assert.Contains(t, taskNames, "gen")
		assert.Contains(t, taskNames, "build")
	})

	t.Run("make task fulfills make target", func(t *testing.T) {
		var makeTask *toolchain.TaskDef
		for i := range tc.Tasks {
			if tc.Tasks[i].Name == "make" {
				makeTask = &tc.Tasks[i]
				break
			}
		}
		require.NotNil(t, makeTask)
		assert.Contains(t, makeTask.Fulfills, "make")
		assert.NotNil(t, makeTask.Handler)
	})

	t.Run("gen task fulfills gen target", func(t *testing.T) {
		var genTask *toolchain.TaskDef
		for i := range tc.Tasks {
			if tc.Tasks[i].Name == "gen" {
				genTask = &tc.Tasks[i]
				break
			}
		}
		require.NotNil(t, genTask)
		assert.Contains(t, genTask.Fulfills, "gen")
		assert.NotNil(t, genTask.Handler)
	})

	t.Run("build task fulfills build target", func(t *testing.T) {
		var buildTask *toolchain.TaskDef
		for i := range tc.Tasks {
			if tc.Tasks[i].Name == "build" {
				buildTask = &tc.Tasks[i]
				break
			}
		}
		require.NotNil(t, buildTask)
		assert.Contains(t, buildTask.Fulfills, "build")
		assert.NotNil(t, buildTask.Handler)
	})
}

func TestGolangTargets(t *testing.T) {
	targets := GolangTargets()

	t.Run("has three targets", func(t *testing.T) {
		assert.Len(t, targets, 3)
	})

	t.Run("make target produces morphir-ir", func(t *testing.T) {
		var makeTarget *toolchain.Target
		for i := range targets {
			if targets[i].Name == "make" {
				makeTarget = &targets[i]
				break
			}
		}
		require.NotNil(t, makeTarget)
		assert.Contains(t, makeTarget.Produces, "morphir-ir")
	})

	t.Run("gen target requires morphir-ir", func(t *testing.T) {
		var genTarget *toolchain.Target
		for i := range targets {
			if targets[i].Name == "gen" {
				genTarget = &targets[i]
				break
			}
		}
		require.NotNil(t, genTarget)
		assert.Contains(t, genTarget.Requires, "morphir-ir")
		assert.Contains(t, genTarget.Variants, "golang")
	})
}

func TestRegister(t *testing.T) {
	registry := toolchain.NewRegistry()

	Register(registry)

	t.Run("Golang toolchain is registered", func(t *testing.T) {
		tc, ok := registry.GetToolchain("golang")
		assert.True(t, ok)
		assert.Equal(t, "golang", tc.Name)
	})

	t.Run("targets are registered", func(t *testing.T) {
		makeTarget, ok := registry.GetTarget("make")
		assert.True(t, ok)
		assert.Equal(t, "make", makeTarget.Name)

		genTarget, ok := registry.GetTarget("gen")
		assert.True(t, ok)
		assert.Equal(t, "gen", genTarget.Name)

		buildTarget, ok := registry.GetTarget("build")
		assert.True(t, ok)
		assert.Equal(t, "build", buildTarget.Name)
	})
}

func TestMakeHandler(t *testing.T) {
	handler := makeMakeHandler()
	require.NotNil(t, handler)

	t.Run("returns warning for unimplemented frontend", func(t *testing.T) {
		// Create pipeline context
		mount := vfs.NewOSMount("test", vfs.MountRW, "/tmp", vfs.MustVPath("/"))
		overlay := vfs.NewOverlayVFS([]vfs.Mount{mount})
		ctx := pipeline.NewContext("/tmp", 0, pipeline.ModeDefault, overlay)

		input := toolchain.TaskInput{
			Options: map[string]any{
				"source": `package main

func main() {
	println("Hello, World!")
}`,
			},
		}

		result := handler(ctx, input)

		// Should have warning about unimplemented frontend
		assert.Len(t, result.Diagnostics, 1)
		assert.Equal(t, pipeline.SeverityWarn, result.Diagnostics[0].Severity)
		assert.Contains(t, result.Diagnostics[0].Message, "not yet implemented")
	})
}

func TestGenHandler(t *testing.T) {
	handler := makeGenHandler()
	require.NotNil(t, handler)

	t.Run("requires modulePath option", func(t *testing.T) {
		mount := vfs.NewOSMount("test", vfs.MountRW, "/tmp", vfs.MustVPath("/"))
		overlay := vfs.NewOverlayVFS([]vfs.Mount{mount})
		ctx := pipeline.NewContext("/tmp", 0, pipeline.ModeDefault, overlay)

		input := toolchain.TaskInput{
			Options: map[string]any{
				"outputDir": "/output",
				// modulePath is missing
			},
		}

		result := handler(ctx, input)

		// Should have an error about missing modulePath
		assert.NotNil(t, result.Error)
		assert.Contains(t, result.Error.Error(), "module path is required")
	})

	t.Run("requires outputDir option", func(t *testing.T) {
		mount := vfs.NewOSMount("test", vfs.MountRW, "/tmp", vfs.MustVPath("/"))
		overlay := vfs.NewOverlayVFS([]vfs.Mount{mount})
		ctx := pipeline.NewContext("/tmp", 0, pipeline.ModeDefault, overlay)

		input := toolchain.TaskInput{
			Options: map[string]any{
				"modulePath": "github.com/example/test",
				// outputDir is missing
			},
		}

		result := handler(ctx, input)

		// Should have an error about missing outputDir
		assert.NotNil(t, result.Error)
		assert.Contains(t, result.Error.Error(), "output directory is required")
	})

	t.Run("generates Go code from module", func(t *testing.T) {
		mount := vfs.NewOSMount("test", vfs.MountRW, "/tmp", vfs.MustVPath("/"))
		overlay := vfs.NewOverlayVFS([]vfs.Mount{mount})
		ctx := pipeline.NewContext("/tmp", 0, pipeline.ModeDefault, overlay)

		// Create a minimal Morphir IR module for testing
		module := ir.NewModuleDefinition[any, any](
			nil, // types
			nil, // values
			nil, // documentation
		)

		input := toolchain.TaskInput{
			Options: map[string]any{
				"modulePath": "github.com/example/test",
				"outputDir":  "/output",
				"module":     module,
			},
		}

		result := handler(ctx, input)

		// Should succeed without error
		assert.Nil(t, result.Error)

		// Should have outputs
		assert.NotNil(t, result.Outputs)
		assert.NotNil(t, result.Outputs["generatedFiles"])
		assert.NotNil(t, result.Outputs["fileCount"])
	})
}

func TestBuildHandler(t *testing.T) {
	handler := makeBuildHandler()
	require.NotNil(t, handler)

	t.Run("requires irPath option", func(t *testing.T) {
		mount := vfs.NewOSMount("test", vfs.MountRW, "/tmp", vfs.MustVPath("/"))
		overlay := vfs.NewOverlayVFS([]vfs.Mount{mount})
		ctx := pipeline.NewContext("/tmp", 0, pipeline.ModeDefault, overlay)

		input := toolchain.TaskInput{
			Options: map[string]any{
				"outputDir":  "/output",
				"modulePath": "github.com/example/test",
				// irPath is missing
			},
		}

		result := handler(ctx, input)

		// Should have an error about missing irPath
		assert.NotNil(t, result.Error)
		assert.Contains(t, result.Error.Error(), "IR path is required")
	})

	t.Run("requires outputDir option", func(t *testing.T) {
		mount := vfs.NewOSMount("test", vfs.MountRW, "/tmp", vfs.MustVPath("/"))
		overlay := vfs.NewOverlayVFS([]vfs.Mount{mount})
		ctx := pipeline.NewContext("/tmp", 0, pipeline.ModeDefault, overlay)

		input := toolchain.TaskInput{
			Options: map[string]any{
				"irPath":     "/path/to/ir.json",
				"modulePath": "github.com/example/test",
				// outputDir is missing
			},
		}

		result := handler(ctx, input)

		// Should have an error about missing outputDir
		assert.NotNil(t, result.Error)
		assert.Contains(t, result.Error.Error(), "output directory is required")
	})
}

func TestGetBoolOption(t *testing.T) {
	t.Run("returns value when present", func(t *testing.T) {
		opts := map[string]any{"flag": true}
		assert.True(t, getBoolOption(opts, "flag", false))

		opts = map[string]any{"flag": false}
		assert.False(t, getBoolOption(opts, "flag", true))
	})

	t.Run("returns default when absent", func(t *testing.T) {
		opts := map[string]any{}
		assert.True(t, getBoolOption(opts, "missing", true))
		assert.False(t, getBoolOption(opts, "missing", false))
	})

	t.Run("returns default when wrong type", func(t *testing.T) {
		opts := map[string]any{"flag": "not a bool"}
		assert.True(t, getBoolOption(opts, "flag", true))
	})
}

func TestGetStringOption(t *testing.T) {
	t.Run("returns value when present", func(t *testing.T) {
		opts := map[string]any{"key": "value"}
		assert.Equal(t, "value", getStringOption(opts, "key", "default"))
	})

	t.Run("returns default when absent", func(t *testing.T) {
		opts := map[string]any{}
		assert.Equal(t, "default", getStringOption(opts, "missing", "default"))
	})

	t.Run("returns default when wrong type", func(t *testing.T) {
		opts := map[string]any{"key": 123}
		assert.Equal(t, "default", getStringOption(opts, "key", "default"))
	})
}

func TestGetIntOption(t *testing.T) {
	t.Run("returns value when present as int", func(t *testing.T) {
		opts := map[string]any{"num": 42}
		assert.Equal(t, 42, getIntOption(opts, "num", 0))
	})

	t.Run("returns value when present as float64", func(t *testing.T) {
		opts := map[string]any{"num": float64(42)}
		assert.Equal(t, 42, getIntOption(opts, "num", 0))
	})

	t.Run("returns default when absent", func(t *testing.T) {
		opts := map[string]any{}
		assert.Equal(t, 10, getIntOption(opts, "missing", 10))
	})

	t.Run("returns default when wrong type", func(t *testing.T) {
		opts := map[string]any{"num": "not a number"}
		assert.Equal(t, 10, getIntOption(opts, "num", 10))
	})
}

func TestValidateGenOptions(t *testing.T) {
	t.Run("returns error when modulePath missing", func(t *testing.T) {
		opts := map[string]any{}
		err := ValidateGenOptions(opts)
		assert.Error(t, err)
		assert.Contains(t, err.Error(), "modulePath")
	})

	t.Run("returns nil when modulePath present", func(t *testing.T) {
		opts := map[string]any{"modulePath": "github.com/example/test"}
		err := ValidateGenOptions(opts)
		assert.NoError(t, err)
	})
}
