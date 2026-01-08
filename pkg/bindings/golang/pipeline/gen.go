package pipeline

import (
	"fmt"
	"path/filepath"

	"github.com/finos/morphir/pkg/bindings/golang/domain"
	"github.com/finos/morphir/pkg/pipeline"
)

// NewGenStep creates the Go "gen" step (Morphir IR → Go code).
// This step generates Go source code from Morphir IR.
func NewGenStep() pipeline.Step[GenInput, GenOutput] {
	return pipeline.NewStep[GenInput, GenOutput](
		"golang-gen",
		"Generates Go code from Morphir IR",
		func(ctx pipeline.Context, in GenInput) (GenOutput, pipeline.StepResult) {
			var result pipeline.StepResult
			var output GenOutput

			// Validate input
			if in.OutputDir.String() == "" {
				result.Diagnostics = []pipeline.Diagnostic{
					DiagnosticError(
						CodeGenerationError,
						"output directory is required",
						"golang-gen",
					),
				}
				result.Err = fmt.Errorf("output directory is required")
				return output, result
			}

			if in.Options.ModulePath == "" {
				result.Diagnostics = []pipeline.Diagnostic{
					DiagnosticError(
						CodeGenerationError,
						"module path is required",
						"golang-gen",
					),
				}
				result.Err = fmt.Errorf("module path is required")
				return output, result
			}

			// Initialize output
			output = GenOutput{
				GeneratedFiles: make(map[string]string),
				ModuleFiles:    []pipeline.Artifact{},
			}

			// Convert IR to Go domain model
			packageName := "generated"
			goPkg, warnings := domain.ConvertModuleToPackage(
				in.Module,
				in.Options.ModulePath,
				packageName,
			)

			// Add warnings as diagnostics
			for _, warning := range warnings {
				result.Diagnostics = append(result.Diagnostics, DiagnosticWarn(
					CodeTypeMappingLost,
					warning,
					"golang-gen",
				))
			}

			// Generate Go source code
			sourceCode, err := domain.EmitPackage(goPkg)
			if err != nil {
				result.Diagnostics = append(result.Diagnostics, DiagnosticError(
					CodeFormatError,
					fmt.Sprintf("failed to format generated code: %v", err),
					"golang-gen",
				))
				result.Err = err
				return output, result
			}

			// Add generated source file
			sourceFilePath := filepath.Join(packageName, packageName+".go")
			output.GeneratedFiles[sourceFilePath] = sourceCode

			// Create artifact for source file
			sourceArtifactPath, err := in.OutputDir.Join(sourceFilePath)
			if err != nil {
				result.Diagnostics = append(result.Diagnostics, DiagnosticError(
					CodeGenerationError,
					fmt.Sprintf("failed to create artifact path: %v", err),
					"golang-gen",
				))
				result.Err = err
				return output, result
			}
			sourceArtifact := pipeline.Artifact{
				Kind:        pipeline.ArtifactCodegen,
				Path:        sourceArtifactPath,
				ContentType: "text/x-go",
				Content:     []byte(sourceCode),
			}
			result.Artifacts = append(result.Artifacts, sourceArtifact)

			// Generate go.mod file
			goModule := domain.GoModule{
				ModulePath:   in.Options.ModulePath,
				GoVersion:    "1.25",
				Packages:     []domain.GoPackage{goPkg},
				Dependencies: make(map[string]string),
			}

			goModContent := domain.EmitGoMod(goModule)
			output.GeneratedFiles["go.mod"] = goModContent

			// Create artifact for go.mod
			goModPath, err := in.OutputDir.Join("go.mod")
			if err != nil {
				result.Diagnostics = append(result.Diagnostics, DiagnosticError(
					CodeGenerationError,
					fmt.Sprintf("failed to create go.mod path: %v", err),
					"golang-gen",
				))
				result.Err = err
				return output, result
			}
			goModArtifact := pipeline.Artifact{
				Kind:        pipeline.ArtifactMetadata,
				Path:        goModPath,
				ContentType: "text/plain",
				Content:     []byte(goModContent),
			}
			result.Artifacts = append(result.Artifacts, goModArtifact)
			output.ModuleFiles = append(output.ModuleFiles, goModArtifact)

			// Generate go.work if workspace mode
			if in.Options.Workspace {
				workspace := domain.GoWorkspace{
					Modules:   []domain.GoModule{goModule},
					GoVersion: "1.25",
				}
				goWorkContent := domain.EmitGoWork(workspace)
				output.GeneratedFiles["go.work"] = goWorkContent

				goWorkPath, err := in.OutputDir.Join("go.work")
				if err != nil {
					result.Diagnostics = append(result.Diagnostics, DiagnosticError(
						CodeGenerationError,
						fmt.Sprintf("failed to create go.work path: %v", err),
						"golang-gen",
					))
					result.Err = err
					return output, result
				}
				goWorkArtifact := pipeline.Artifact{
					Kind:        pipeline.ArtifactMetadata,
					Path:        goWorkPath,
					ContentType: "text/plain",
					Content:     []byte(goWorkContent),
				}
				result.Artifacts = append(result.Artifacts, goWorkArtifact)
				output.WorkspaceFile = &goWorkArtifact
			}

			// Add info diagnostic about generation success
			result.Diagnostics = append(result.Diagnostics, DiagnosticInfo(
				CodeGenerationError,
				fmt.Sprintf("Generated %d files for module %s", len(output.GeneratedFiles), in.Options.ModulePath),
				"golang-gen",
			))

			return output, result
		},
	)
}
