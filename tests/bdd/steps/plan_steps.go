package steps

import (
	"context"
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"github.com/cucumber/godog"
)

// RegisterPlanSteps registers step definitions for the plan command.
func RegisterPlanSteps(sc *godog.ScenarioContext) {
	// Setup steps
	sc.Step(`^a morphir\.toml with a build workflow$`, aMorphirTomlWithBuildWorkflow)
	sc.Step(`^a morphir\.toml with a multi-stage workflow$`, aMorphirTomlWithMultiStageWorkflow)
	sc.Step(`^a morphir\.toml with dependent tasks$`, aMorphirTomlWithDependentTasks)
	sc.Step(`^a morphir\.toml with tasks having inputs$`, aMorphirTomlWithTasksHavingInputs)
	sc.Step(`^a morphir\.toml with parallel stages$`, aMorphirTomlWithParallelStages)
	sc.Step(`^the morphir-elm toolchain is available$`, theMorphirElmToolchainIsAvailable)

	// Command execution
	sc.Step(`^I run morphir plan$`, iRunMorphirPlan)
	sc.Step(`^I run morphir plan --help$`, iRunMorphirPlanHelp)
	sc.Step(`^I run morphir plan ([a-z]+)$`, iRunMorphirPlanWorkflow)
	sc.Step(`^I run morphir plan ([a-z]+) --mermaid$`, iRunMorphirPlanWithMermaid)
	sc.Step(`^I run morphir plan ([a-z]+) --mermaid ([^\s]+)$`, iRunMorphirPlanWithMermaidPath)
	sc.Step(`^I run morphir plan ([a-z]+) --mermaid --mermaid-path ([^\s]+) --show-inputs --show-outputs$`, iRunMorphirPlanWithShowInputsOutputs)
	sc.Step(`^I run morphir plan ([a-z]+) --dry-run$`, iRunMorphirPlanDryRun)
	sc.Step(`^I run morphir plan ([a-z]+) --run --mermaid ([^\s]+)$`, iRunMorphirPlanRunWithMermaid)
	sc.Step(`^I run morphir plan ([a-z]+) --explain ([^\s]+)$`, iRunMorphirPlanExplain)

	// Assertions for files
	sc.Step(`^a mermaid file should exist at "([^"]*)"$`, aMermaidFileShouldExist)
	sc.Step(`^the mermaid file should contain "([^"]*)"$`, theMermaidFileShouldContain)
	sc.Step(`^a file should exist at "([^"]*)"$`, aFileShouldExist)
	sc.Step(`^the file "([^"]*)" should contain "([^"]*)"$`, theFileShouldContain)
}

// Helper to write a morphir.toml config file
func writeMorphirToml(ctx context.Context, content string) error {
	ctc, err := GetCLITestContext(ctx)
	if err != nil {
		return err
	}

	configPath := filepath.Join(ctc.WorkDir, "morphir.toml")
	return os.WriteFile(configPath, []byte(content), 0644)
}

// Step implementations

func aMorphirTomlWithBuildWorkflow(ctx context.Context) error {
	// Use unique target name "elm-make" to avoid conflicts with built-in golang/wit toolchains
	config := `
[workflows.build]
description = "Standard build workflow"

[[workflows.build.stages]]
name = "frontend"
targets = ["elm-make"]

[toolchain.morphir-elm]
version = "2.90.0"

[toolchain.morphir-elm.acquire]
backend = "npx"
package = "morphir-elm"

[toolchain.morphir-elm.tasks.make]
exec = "morphir-elm"
args = ["make", "-o", "{outputs.ir}"]
fulfills = ["elm-make"]

[toolchain.morphir-elm.tasks.make.inputs]
files = ["elm.json", "src/**/*.elm"]

[toolchain.morphir-elm.tasks.make.outputs.ir]
path = "morphir-ir.json"
type = "morphir-ir"
`
	return writeMorphirToml(ctx, config)
}

func aMorphirTomlWithMultiStageWorkflow(ctx context.Context) error {
	// Use unique target names to avoid conflicts with built-in toolchains
	config := `
[workflows.ci]
description = "CI workflow"

[[workflows.ci.stages]]
name = "frontend"
targets = ["elm-make"]

[[workflows.ci.stages]]
name = "backend"
targets = ["elm-gen:Scala"]

[toolchain.morphir-elm]
version = "2.90.0"

[toolchain.morphir-elm.acquire]
backend = "npx"
package = "morphir-elm"

[toolchain.morphir-elm.tasks.make]
exec = "morphir-elm"
args = ["make"]
fulfills = ["elm-make"]

[toolchain.morphir-elm.tasks.gen]
exec = "morphir-elm"
args = ["gen"]
fulfills = ["elm-gen"]
variants = ["Scala", "TypeScript"]
`
	return writeMorphirToml(ctx, config)
}

func aMorphirTomlWithDependentTasks(ctx context.Context) error {
	// Use unique target names to avoid conflicts with built-in toolchains
	config := `
[workflows.build]
description = "Build with dependencies"

[[workflows.build.stages]]
name = "frontend"
targets = ["elm-make"]

[[workflows.build.stages]]
name = "backend"
targets = ["elm-gen:Scala"]

[toolchain.morphir-elm]
version = "2.90.0"

[toolchain.morphir-elm.acquire]
backend = "npx"
package = "morphir-elm"

[toolchain.morphir-elm.tasks.make]
exec = "morphir-elm"
args = ["make"]
fulfills = ["elm-make"]

[toolchain.morphir-elm.tasks.make.outputs.ir]
path = "morphir-ir.json"
type = "morphir-ir"

[toolchain.morphir-elm.tasks.gen]
exec = "morphir-elm"
args = ["gen", "-t", "scala"]
fulfills = ["elm-gen"]
variants = ["Scala"]

[toolchain.morphir-elm.tasks.gen.inputs.artifacts]
ir = "@morphir-elm/make:ir"
`
	return writeMorphirToml(ctx, config)
}

func aMorphirTomlWithTasksHavingInputs(ctx context.Context) error {
	// Use unique target name to avoid conflicts with built-in toolchains
	config := `
[workflows.build]
description = "Build with inputs"

[[workflows.build.stages]]
name = "frontend"
targets = ["elm-make"]

[toolchain.morphir-elm]
version = "2.90.0"

[toolchain.morphir-elm.acquire]
backend = "npx"
package = "morphir-elm"

[toolchain.morphir-elm.tasks.make]
exec = "morphir-elm"
args = ["make"]
fulfills = ["elm-make"]

[toolchain.morphir-elm.tasks.make.inputs]
files = ["elm.json", "src/**/*.elm"]

[toolchain.morphir-elm.tasks.make.outputs.ir]
path = "morphir-ir.json"
type = "morphir-ir"
`
	return writeMorphirToml(ctx, config)
}

func aMorphirTomlWithParallelStages(ctx context.Context) error {
	// Use unique target names to avoid conflicts with built-in toolchains
	config := `
[workflows.build]
description = "Build with parallel stage"

[[workflows.build.stages]]
name = "frontend"
targets = ["elm-make"]

[[workflows.build.stages]]
name = "backend"
targets = ["elm-gen:Scala", "elm-gen:TypeScript"]
parallel = true

[toolchain.morphir-elm]
version = "2.90.0"

[toolchain.morphir-elm.acquire]
backend = "npx"
package = "morphir-elm"

[toolchain.morphir-elm.tasks.make]
exec = "morphir-elm"
args = ["make"]
fulfills = ["elm-make"]

[toolchain.morphir-elm.tasks.gen]
exec = "morphir-elm"
args = ["gen"]
fulfills = ["elm-gen"]
variants = ["Scala", "TypeScript"]
`
	return writeMorphirToml(ctx, config)
}

func theMorphirElmToolchainIsAvailable(ctx context.Context) error {
	// This step verifies morphir-elm is available via npx
	// For now, we just mark it as available - real execution would check npx
	return nil
}

// Command execution steps

func iRunMorphirPlan(ctx context.Context) error {
	ctc, err := GetCLITestContext(ctx)
	if err != nil {
		return err
	}
	return runMorphirCommand(ctc, "plan")
}

func iRunMorphirPlanHelp(ctx context.Context) error {
	ctc, err := GetCLITestContext(ctx)
	if err != nil {
		return err
	}
	return runMorphirCommand(ctc, "plan", "--help")
}

func iRunMorphirPlanWorkflow(ctx context.Context, workflow string) error {
	ctc, err := GetCLITestContext(ctx)
	if err != nil {
		return err
	}
	return runMorphirCommand(ctc, "plan", workflow)
}

func iRunMorphirPlanWithMermaid(ctx context.Context, workflow string) error {
	ctc, err := GetCLITestContext(ctx)
	if err != nil {
		return err
	}
	return runMorphirCommand(ctc, "plan", workflow, "--mermaid")
}

func iRunMorphirPlanWithMermaidPath(ctx context.Context, workflow, path string) error {
	ctc, err := GetCLITestContext(ctx)
	if err != nil {
		return err
	}
	return runMorphirCommand(ctc, "plan", workflow, "--mermaid", "--mermaid-path", path)
}

func iRunMorphirPlanWithShowInputsOutputs(ctx context.Context, workflow, path string) error {
	ctc, err := GetCLITestContext(ctx)
	if err != nil {
		return err
	}
	return runMorphirCommand(ctc, "plan", workflow, "--mermaid", "--mermaid-path", path, "--show-inputs", "--show-outputs")
}

func iRunMorphirPlanDryRun(ctx context.Context, workflow string) error {
	ctc, err := GetCLITestContext(ctx)
	if err != nil {
		return err
	}
	return runMorphirCommand(ctc, "plan", workflow, "--dry-run")
}

func iRunMorphirPlanRunWithMermaid(ctx context.Context, workflow, path string) error {
	ctc, err := GetCLITestContext(ctx)
	if err != nil {
		return err
	}
	return runMorphirCommand(ctc, "plan", workflow, "--run", "--mermaid", "--mermaid-path", path)
}

func iRunMorphirPlanExplain(ctx context.Context, workflow, task string) error {
	ctc, err := GetCLITestContext(ctx)
	if err != nil {
		return err
	}
	return runMorphirCommand(ctc, "plan", workflow, "--explain", task)
}

// File assertion steps

// mermaidFilePath stores the path to the last referenced mermaid file
var mermaidFilePath string

func aMermaidFileShouldExist(ctx context.Context, path string) error {
	ctc, err := GetCLITestContext(ctx)
	if err != nil {
		return err
	}

	fullPath := filepath.Join(ctc.WorkDir, path)
	mermaidFilePath = fullPath

	if _, err := os.Stat(fullPath); os.IsNotExist(err) {
		return fmt.Errorf("mermaid file does not exist: %s", fullPath)
	}

	return nil
}

func theMermaidFileShouldContain(ctx context.Context, expected string) error {
	if mermaidFilePath == "" {
		return fmt.Errorf("no mermaid file path set")
	}

	content, err := os.ReadFile(mermaidFilePath)
	if err != nil {
		return fmt.Errorf("failed to read mermaid file: %w", err)
	}

	if !strings.Contains(string(content), expected) {
		return fmt.Errorf("mermaid file does not contain %q\nactual content: %s", expected, content)
	}

	return nil
}

func aFileShouldExist(ctx context.Context, path string) error {
	ctc, err := GetCLITestContext(ctx)
	if err != nil {
		return err
	}

	fullPath := filepath.Join(ctc.WorkDir, path)
	if _, err := os.Stat(fullPath); os.IsNotExist(err) {
		return fmt.Errorf("file does not exist: %s", fullPath)
	}

	return nil
}

func theFileShouldContain(ctx context.Context, path, expected string) error {
	ctc, err := GetCLITestContext(ctx)
	if err != nil {
		return err
	}

	fullPath := filepath.Join(ctc.WorkDir, path)
	content, err := os.ReadFile(fullPath)
	if err != nil {
		return fmt.Errorf("failed to read file %s: %w", fullPath, err)
	}

	if !strings.Contains(string(content), expected) {
		return fmt.Errorf("file %s does not contain %q\nactual content: %s", path, expected, content)
	}

	return nil
}
