package steps

import (
	"context"
	"os"
	"path/filepath"

	"github.com/cucumber/godog"
)

// RegisterWorkflowSteps registers step definitions for workflow execution tests.
func RegisterWorkflowSteps(sc *godog.ScenarioContext) {
	// morphir.toml setup steps
	sc.Step(`^a morphir\.toml using the built-in morphir-elm toolchain:$`, aMorphirTomlUsingBuiltInToolchain)
	sc.Step(`^a minimal morphir\.toml for build workflow:$`, aMinimalMorphirTomlForBuild)
	sc.Step(`^a morphir\.toml with make and gen stages:$`, aMorphirTomlWithMakeAndGenStages)
}

// aMorphirTomlUsingBuiltInToolchain creates a morphir.toml that uses the built-in morphir-elm toolchain.
// The content is provided as a docstring and we append no additional configuration since
// the toolchain is built-in.
func aMorphirTomlUsingBuiltInToolchain(ctx context.Context, content *godog.DocString) error {
	ctc, err := GetCLITestContext(ctx)
	if err != nil {
		return err
	}

	configPath := filepath.Join(ctc.WorkDir, "morphir.toml")
	return os.WriteFile(configPath, []byte(content.Content), 0644)
}

// aMinimalMorphirTomlForBuild creates a minimal morphir.toml with just workflow definition.
// This tests that the built-in toolchains work without explicit configuration.
func aMinimalMorphirTomlForBuild(ctx context.Context, content *godog.DocString) error {
	ctc, err := GetCLITestContext(ctx)
	if err != nil {
		return err
	}

	configPath := filepath.Join(ctc.WorkDir, "morphir.toml")
	return os.WriteFile(configPath, []byte(content.Content), 0644)
}

// aMorphirTomlWithMakeAndGenStages creates a morphir.toml with both make and gen stages.
func aMorphirTomlWithMakeAndGenStages(ctx context.Context, content *godog.DocString) error {
	ctc, err := GetCLITestContext(ctx)
	if err != nil {
		return err
	}

	configPath := filepath.Join(ctc.WorkDir, "morphir.toml")
	return os.WriteFile(configPath, []byte(content.Content), 0644)
}
