package toolchain

import (
	"testing"

	"github.com/finos/morphir/pkg/pipeline"
	"github.com/finos/morphir/pkg/toolchain"
	"github.com/finos/morphir/pkg/vfs"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestWITToolchain(t *testing.T) {
	tc := WITToolchain()

	t.Run("has correct name", func(t *testing.T) {
		assert.Equal(t, "wit", tc.Name)
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

func TestWITTargets(t *testing.T) {
	targets := WITTargets()

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
	})
}

func TestRegister(t *testing.T) {
	registry := toolchain.NewRegistry()

	Register(registry)

	t.Run("WIT toolchain is registered", func(t *testing.T) {
		tc, ok := registry.GetToolchain("wit")
		assert.True(t, ok)
		assert.Equal(t, "wit", tc.Name)
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

	t.Run("executes with valid WIT source", func(t *testing.T) {
		// Create pipeline context
		mount := vfs.NewOSMount("test", vfs.MountRW, "/tmp", vfs.MustVPath("/"))
		overlay := vfs.NewOverlayVFS([]vfs.Mount{mount})
		ctx := pipeline.NewContext("/tmp", 0, pipeline.ModeDefault, overlay)

		input := toolchain.TaskInput{
			Options: map[string]any{
				"source": `package test:example;

interface example {
    record user {
        id: string,
        name: string,
    }
}`,
			},
		}

		result := handler(ctx, input)

		// Should succeed (no error)
		assert.Nil(t, result.Error)

		// Should have outputs
		assert.NotNil(t, result.Outputs)
		assert.NotNil(t, result.Outputs["module"])
	})

	t.Run("handles invalid WIT source", func(t *testing.T) {
		mount := vfs.NewOSMount("test", vfs.MountRW, "/tmp", vfs.MustVPath("/"))
		overlay := vfs.NewOverlayVFS([]vfs.Mount{mount})
		ctx := pipeline.NewContext("/tmp", 0, pipeline.ModeDefault, overlay)

		input := toolchain.TaskInput{
			Options: map[string]any{
				"source": "invalid WIT syntax {{{",
			},
		}

		result := handler(ctx, input)

		// Should have an error
		assert.NotNil(t, result.Error)
	})
}

func TestBuildHandler(t *testing.T) {
	handler := makeBuildHandler()
	require.NotNil(t, handler)

	t.Run("executes full pipeline with valid WIT", func(t *testing.T) {
		mount := vfs.NewOSMount("test", vfs.MountRW, "/tmp", vfs.MustVPath("/"))
		overlay := vfs.NewOverlayVFS([]vfs.Mount{mount})
		ctx := pipeline.NewContext("/tmp", 0, pipeline.ModeDefault, overlay)

		input := toolchain.TaskInput{
			Options: map[string]any{
				"source": `package test:example;

interface example {
    type user-id = string;
}`,
			},
		}

		result := handler(ctx, input)

		// Should succeed
		assert.Nil(t, result.Error)

		// Should have outputs
		assert.NotNil(t, result.Outputs)
		assert.NotNil(t, result.Outputs["source"])

		// Should indicate round-trip validity
		_, hasRoundTrip := result.Outputs["roundTripValid"]
		assert.True(t, hasRoundTrip)
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
