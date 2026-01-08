package main

import (
	"fmt"
	"os"

	"github.com/finos/morphir/pkg/bindings/golang/domain"
	"github.com/finos/morphir/pkg/bindings/golang/pipeline"
	"github.com/finos/morphir/pkg/models/ir"
	pipelinepkg "github.com/finos/morphir/pkg/pipeline"
	"github.com/finos/morphir/pkg/vfs"
)

// This example demonstrates the IR to Go code generation.
func main() {
	// Create a simple type alias: type UserID = String
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
	documented := ir.NewDocumented("UserID is a unique identifier for users", typeAlias)
	accessControlled := ir.Public(documented)
	moduleType := ir.ModuleDefinitionTypeFromParts[any](userIDName, accessControlled)

	module := ir.NewModuleDefinition[any, any](
		[]ir.ModuleDefinitionType[any]{moduleType},
		nil,
		nil,
	)

	// Generate Go code
	fmt.Println("=== Generating Go code from Morphir IR ===")

	pkg, warnings := domain.ConvertModuleToPackage(module, "github.com/example/myapp", "domain")

	fmt.Println("Package:", pkg.Name)
	fmt.Println("Type Count:", len(pkg.Types))

	if len(warnings) > 0 {
		fmt.Println("\nWarnings:")
		for _, w := range warnings {
			fmt.Println(" -", w)
		}
	}

	fmt.Println("\n=== Generated Go Source ===")
	source, err := domain.EmitPackage(pkg)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error: %v\n", err)
		os.Exit(1)
	}
	fmt.Println(source)

	// Using pipeline step
	fmt.Println("\n=== Using Pipeline Step ===")

	step := pipeline.NewGenStep()
	ctx := pipelinepkg.NewContext("/tmp", 1, pipelinepkg.ModeDefault, nil)
	outputDir := vfs.MustVPath("/output")

	input := pipeline.GenInput{
		Module:    module,
		OutputDir: outputDir,
		Options: pipeline.GenOptions{
			ModulePath: "github.com/example/myapp",
		},
	}

	output, result := step.Execute(ctx, input)

	if result.Err != nil {
		fmt.Fprintf(os.Stderr, "Error: %v\n", result.Err)
		os.Exit(1)
	}

	fmt.Println("Generated Files:")
	for path := range output.GeneratedFiles {
		fmt.Println(" -", path)
	}

	fmt.Println("\n=== go.mod Content ===")
	fmt.Println(output.GeneratedFiles["go.mod"])
}
