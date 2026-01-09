package toolchain

import (
	"testing"

	"github.com/finos/morphir/pkg/toolchain"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestMorphirElmToolchain(t *testing.T) {
	tc := MorphirElmToolchain()

	t.Run("has correct name", func(t *testing.T) {
		assert.Equal(t, "morphir-elm", tc.Name)
	})

	t.Run("is external type", func(t *testing.T) {
		assert.Equal(t, toolchain.ToolchainTypeExternal, tc.Type)
	})

	t.Run("uses npx backend", func(t *testing.T) {
		assert.Equal(t, "npx", tc.Acquire.Backend)
		assert.Equal(t, "morphir-elm", tc.Acquire.Package)
		assert.Equal(t, DefaultVersion, tc.Acquire.Version)
	})

	t.Run("has default version", func(t *testing.T) {
		assert.Equal(t, DefaultVersion, tc.Version)
	})

	t.Run("has two tasks", func(t *testing.T) {
		assert.Len(t, tc.Tasks, 2)

		taskNames := make([]string, len(tc.Tasks))
		for i, task := range tc.Tasks {
			taskNames[i] = task.Name
		}
		assert.Contains(t, taskNames, "make")
		assert.Contains(t, taskNames, "gen")
	})

	t.Run("has NODE_OPTIONS env var", func(t *testing.T) {
		assert.Contains(t, tc.Env, "NODE_OPTIONS")
	})
}

func TestMorphirElmToolchainWithVersion(t *testing.T) {
	customVersion := "2.85.0"
	tc := MorphirElmToolchainWithVersion(customVersion)

	t.Run("uses custom version", func(t *testing.T) {
		assert.Equal(t, customVersion, tc.Version)
		assert.Equal(t, customVersion, tc.Acquire.Version)
	})
}

func TestMakeTask(t *testing.T) {
	tc := MorphirElmToolchain()

	var makeTask *toolchain.TaskDef
	for i := range tc.Tasks {
		if tc.Tasks[i].Name == "make" {
			makeTask = &tc.Tasks[i]
			break
		}
	}
	require.NotNil(t, makeTask)

	t.Run("fulfills make target", func(t *testing.T) {
		assert.Contains(t, makeTask.Fulfills, "make")
	})

	t.Run("has correct args", func(t *testing.T) {
		assert.Equal(t, []string{"make", "-o", "{outputs.ir}"}, makeTask.Args)
	})

	t.Run("has file inputs", func(t *testing.T) {
		assert.Contains(t, makeTask.Inputs.Files, "elm.json")
		assert.Contains(t, makeTask.Inputs.Files, "src/**/*.elm")
		assert.Contains(t, makeTask.Inputs.Files, "morphir.json")
	})

	t.Run("outputs morphir-ir", func(t *testing.T) {
		irOutput, ok := makeTask.Outputs["ir"]
		require.True(t, ok)
		assert.Equal(t, "morphir-ir.json", irOutput.Path)
		assert.Equal(t, "morphir-ir", irOutput.Type)
	})
}

func TestGenTask(t *testing.T) {
	tc := MorphirElmToolchain()

	var genTask *toolchain.TaskDef
	for i := range tc.Tasks {
		if tc.Tasks[i].Name == "gen" {
			genTask = &tc.Tasks[i]
			break
		}
	}
	require.NotNil(t, genTask)

	t.Run("fulfills gen target", func(t *testing.T) {
		assert.Contains(t, genTask.Fulfills, "gen")
	})

	t.Run("has correct args with variant substitution", func(t *testing.T) {
		assert.Contains(t, genTask.Args, "{variant}")
		assert.Contains(t, genTask.Args, "{inputs.ir}")
		assert.Contains(t, genTask.Args, "{outputs.dir}")
	})

	t.Run("requires IR artifact from make", func(t *testing.T) {
		irArtifact, ok := genTask.Inputs.Artifacts["ir"]
		require.True(t, ok)
		assert.Equal(t, "@morphir-elm/make:ir", irArtifact)
	})

	t.Run("supports expected variants", func(t *testing.T) {
		assert.Contains(t, genTask.Variants, "Scala")
		assert.Contains(t, genTask.Variants, "JsonSchema")
		assert.Contains(t, genTask.Variants, "TypeScript")
		assert.Contains(t, genTask.Variants, "Snowpark")
		assert.Contains(t, genTask.Variants, "Spark")
	})

	t.Run("outputs generated code", func(t *testing.T) {
		dirOutput, ok := genTask.Outputs["dir"]
		require.True(t, ok)
		assert.Equal(t, "dist/{variant}", dirOutput.Path)
		assert.Equal(t, "generated-code", dirOutput.Type)
	})
}

func TestMorphirElmTargets(t *testing.T) {
	targets := MorphirElmTargets()

	t.Run("has two targets", func(t *testing.T) {
		assert.Len(t, targets, 2)
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
		assert.Contains(t, genTarget.Produces, "generated-code")
		assert.Contains(t, genTarget.Variants, "Scala")
	})
}

func TestRegister(t *testing.T) {
	registry := toolchain.NewRegistry()

	Register(registry)

	t.Run("morphir-elm toolchain is registered", func(t *testing.T) {
		tc, ok := registry.GetToolchain("morphir-elm")
		assert.True(t, ok)
		assert.Equal(t, "morphir-elm", tc.Name)
		assert.Equal(t, toolchain.ToolchainTypeExternal, tc.Type)
	})

	t.Run("targets are registered", func(t *testing.T) {
		makeTarget, ok := registry.GetTarget("make")
		assert.True(t, ok)
		assert.Equal(t, "make", makeTarget.Name)

		genTarget, ok := registry.GetTarget("gen")
		assert.True(t, ok)
		assert.Equal(t, "gen", genTarget.Name)
	})
}

func TestRegisterWithVersion(t *testing.T) {
	registry := toolchain.NewRegistry()

	customVersion := "2.85.0"
	RegisterWithVersion(registry, customVersion)

	t.Run("uses custom version", func(t *testing.T) {
		tc, ok := registry.GetToolchain("morphir-elm")
		require.True(t, ok)
		assert.Equal(t, customVersion, tc.Version)
		assert.Equal(t, customVersion, tc.Acquire.Version)
	})
}

func TestValidateOptions(t *testing.T) {
	t.Run("ValidateMakeOptions accepts empty options", func(t *testing.T) {
		err := ValidateMakeOptions(map[string]any{})
		assert.NoError(t, err)
	})

	t.Run("ValidateGenOptions accepts empty options", func(t *testing.T) {
		err := ValidateGenOptions(map[string]any{})
		assert.NoError(t, err)
	})
}
