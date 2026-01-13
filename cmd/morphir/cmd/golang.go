package cmd

import (
	"bufio"
	"encoding/json"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"

	"github.com/charmbracelet/lipgloss"
	golangpipeline "github.com/finos/morphir/pkg/bindings/golang/pipeline"
	"github.com/finos/morphir/pkg/models/ir"
	"github.com/finos/morphir/pkg/pipeline"
	"github.com/finos/morphir/pkg/vfs"
	"github.com/spf13/cobra"
)

// Go command flags
var (
	golangIRFilePath    string
	golangOutputDir     string
	golangModulePath    string
	golangWorkspace     bool
	golangJSON          bool
	golangVerbose       bool
	golangWarningsAsErr bool
	golangSourcePath    string
	golangJSONL         bool   // JSONL output mode (one JSON object per line)
	golangJSONLInput    string // Path to JSONL input file for batch processing
)

// JSONGolangGenOutput represents the JSON output for golang gen command
type JSONGolangGenOutput struct {
	Success        bool                `json:"success"`
	OutputDir      string              `json:"outputDir,omitempty"`
	ModulePath     string              `json:"modulePath,omitempty"`
	GeneratedFiles []string            `json:"generatedFiles,omitempty"`
	FileCount      int                 `json:"fileCount"`
	Error          string              `json:"error,omitempty"`
	Diagnostics    []map[string]string `json:"diagnostics,omitempty"`
}

// JSONGolangMakeOutput represents the JSON output for golang make command
type JSONGolangMakeOutput struct {
	Success     bool                `json:"success"`
	SourcePath  string              `json:"sourcePath,omitempty"`
	Error       string              `json:"error,omitempty"`
	Diagnostics []map[string]string `json:"diagnostics,omitempty"`
}

// JSONGolangBuildOutput represents the JSON output for golang build command
type JSONGolangBuildOutput struct {
	Success        bool                `json:"success"`
	IRPath         string              `json:"irPath,omitempty"`
	OutputDir      string              `json:"outputDir,omitempty"`
	ModulePath     string              `json:"modulePath,omitempty"`
	GeneratedFiles []string            `json:"generatedFiles,omitempty"`
	FileCount      int                 `json:"fileCount"`
	Error          string              `json:"error,omitempty"`
	Diagnostics    []map[string]string `json:"diagnostics,omitempty"`
}

// JSONLGolangInput represents a single input in JSONL batch mode
type JSONLGolangInput struct {
	// Name is an optional identifier for this input (used in output)
	Name string `json:"name,omitempty"`
	// IRFile is a path to a Morphir IR JSON file (for build/gen)
	IRFile string `json:"irFile,omitempty"`
	// SourceFile is a path to a Go source file (for make)
	SourceFile string `json:"sourceFile,omitempty"`
	// OutputDir is the output directory for generated files
	OutputDir string `json:"outputDir,omitempty"`
	// ModulePath is the Go module path for generated go.mod
	ModulePath string `json:"modulePath,omitempty"`
}

// JSONLGolangMakeOutput represents a single make result in JSONL output mode
type JSONLGolangMakeOutput struct {
	Name        string              `json:"name,omitempty"`
	Success     bool                `json:"success"`
	SourcePath  string              `json:"sourcePath,omitempty"`
	Error       string              `json:"error,omitempty"`
	Diagnostics []map[string]string `json:"diagnostics,omitempty"`
}

// JSONLGolangBuildOutput represents a single build result in JSONL output mode
type JSONLGolangBuildOutput struct {
	Name           string              `json:"name,omitempty"`
	Success        bool                `json:"success"`
	IRPath         string              `json:"irPath,omitempty"`
	OutputDir      string              `json:"outputDir,omitempty"`
	ModulePath     string              `json:"modulePath,omitempty"`
	GeneratedFiles []string            `json:"generatedFiles,omitempty"`
	FileCount      int                 `json:"fileCount"`
	Error          string              `json:"error,omitempty"`
	Diagnostics    []map[string]string `json:"diagnostics,omitempty"`
}

var golangCmd = &cobra.Command{
	Use:   "golang",
	Short: "Go code generation operations",
	Long: `Commands for working with Go code generation from Morphir IR.

These commands convert Morphir IR to idiomatic Go code,
generating Go modules, packages, and workspace files.

Available Commands:
  make   - Compile Go source to Morphir IR (not yet implemented)
  gen    - Generate Go code from Morphir IR
  build  - Full pipeline: load IR and generate Go code`,
}

var golangGenCmd = &cobra.Command{
	Use:   "gen [ir-file.json]",
	Short: "Generate Go code from Morphir IR",
	Long: `Generate Go source code from a Morphir IR JSON file.

This command takes a Morphir IR file and generates idiomatic Go code,
including go.mod files and optionally go.work for workspaces.

Examples:
  morphir golang gen morphir-ir.json -o ./generated -m github.com/example/myapp
  morphir golang gen -f ir.json -o ./out -m example.com/pkg --workspace
  morphir golang gen ir.json -o ./out -m mymod --json

Flags:
  -f, --file         Path to Morphir IR JSON file
  -o, --output       Output directory for generated Go code (required)
  -m, --module-path  Go module path for generated go.mod (required)
  -w, --workspace    Enable workspace mode (generates go.work)
  -v, --verbose      Show detailed diagnostics
      --json         Output result as JSON`,
	Args: cobra.MaximumNArgs(1),
	RunE: runGolangGen,
}

var golangMakeCmd = &cobra.Command{
	Use:   "make [source.go]",
	Short: "Compile Go source to Morphir IR (not yet implemented)",
	Long: `Compile Go source code to Morphir IR.

NOTE: This command is a placeholder. Go frontend compilation (Go → Morphir IR)
is not yet implemented. This command exists for API parity with other bindings.

Examples:
  morphir golang make ./src/main.go
  morphir golang make -s ./pkg/domain/ --json

JSONL Batch Mode:
  Process multiple Go sources from a JSONL file (one JSON object per line):

  morphir golang make --jsonl-input sources.jsonl --jsonl

  Input format (sources.jsonl):
    {"name": "pkg1", "sourceFile": "./pkg/domain/types.go"}
    {"name": "pkg2", "sourceFile": "./pkg/service/api.go"}

  Output format (--jsonl):
    {"name": "pkg1", "success": true, "diagnostics": [...]}
    {"name": "pkg2", "success": true, "diagnostics": [...]}

Flags:
  -s, --source       Path to Go source file or directory
  -v, --verbose      Show detailed diagnostics
      --json         Output result as JSON
      --jsonl        Output as JSONL (one JSON object per line)
      --jsonl-input  Path to JSONL file with batch inputs`,
	Args: cobra.MaximumNArgs(1),
	RunE: runGolangMake,
}

var golangBuildCmd = &cobra.Command{
	Use:   "build [ir-file.json]",
	Short: "Full pipeline: load IR and generate Go code",
	Long: `Execute the full Go build pipeline.

This command loads a Morphir IR file and generates Go code in one step.
It combines IR loading with the gen step for convenience.

Examples:
  morphir golang build morphir-ir.json -o ./generated -m github.com/example/myapp
  morphir golang build -f ir.json -o ./out -m example.com/pkg --workspace
  morphir golang build ir.json -o ./out -m mymod --json

JSONL Batch Mode:
  Process multiple IR files from a JSONL file (one JSON object per line):

  morphir golang build --jsonl-input builds.jsonl --jsonl

  Input format (builds.jsonl):
    {"name": "app1", "irFile": "./app1/morphir-ir.json", "outputDir": "./gen/app1", "modulePath": "example.com/app1"}
    {"name": "app2", "irFile": "./app2/morphir-ir.json", "outputDir": "./gen/app2", "modulePath": "example.com/app2"}

  Output format (--jsonl):
    {"name": "app1", "success": true, "fileCount": 5, "generatedFiles": [...], "diagnostics": [...]}
    {"name": "app2", "success": true, "fileCount": 3, "generatedFiles": [...], "diagnostics": [...]}

Flags:
  -f, --file         Path to Morphir IR JSON file
  -o, --output       Output directory for generated Go code (required)
  -m, --module-path  Go module path for generated go.mod (required)
  -w, --workspace    Enable workspace mode (generates go.work)
  -v, --verbose      Show detailed diagnostics
      --json         Output result as JSON
      --jsonl        Output as JSONL (one JSON object per line)
      --jsonl-input  Path to JSONL file with batch inputs`,
	Args: cobra.MaximumNArgs(1),
	RunE: runGolangBuild,
}

func init() {
	// Gen command flags
	golangGenCmd.Flags().StringVarP(&golangIRFilePath, "file", "f", "", "Path to Morphir IR JSON file")
	golangGenCmd.Flags().StringVarP(&golangOutputDir, "output", "o", "", "Output directory for generated Go code")
	golangGenCmd.Flags().StringVarP(&golangModulePath, "module-path", "m", "", "Go module path (e.g., github.com/example/myapp)")
	golangGenCmd.Flags().BoolVarP(&golangWorkspace, "workspace", "w", false, "Enable workspace mode (generates go.work)")
	golangGenCmd.Flags().BoolVarP(&golangVerbose, "verbose", "v", false, "Show detailed diagnostics")
	golangGenCmd.Flags().BoolVar(&golangJSON, "json", false, "Output result as JSON")
	golangGenCmd.Flags().BoolVar(&golangWarningsAsErr, "warnings-as-errors", false, "Treat warnings as errors")

	// Mark required flags for gen
	_ = golangGenCmd.MarkFlagRequired("output")
	_ = golangGenCmd.MarkFlagRequired("module-path")

	// Make command flags
	golangMakeCmd.Flags().StringVarP(&golangSourcePath, "source", "s", "", "Path to Go source file or directory")
	golangMakeCmd.Flags().BoolVarP(&golangVerbose, "verbose", "v", false, "Show detailed diagnostics")
	golangMakeCmd.Flags().BoolVar(&golangJSON, "json", false, "Output result as JSON")
	golangMakeCmd.Flags().BoolVar(&golangJSONL, "jsonl", false, "Output as JSONL (one JSON object per line)")
	golangMakeCmd.Flags().StringVar(&golangJSONLInput, "jsonl-input", "", "Path to JSONL file with batch inputs")
	golangMakeCmd.Flags().BoolVar(&golangWarningsAsErr, "warnings-as-errors", false, "Treat warnings as errors")

	// Build command flags
	golangBuildCmd.Flags().StringVarP(&golangIRFilePath, "file", "f", "", "Path to Morphir IR JSON file")
	golangBuildCmd.Flags().StringVarP(&golangOutputDir, "output", "o", "", "Output directory for generated Go code")
	golangBuildCmd.Flags().StringVarP(&golangModulePath, "module-path", "m", "", "Go module path (e.g., github.com/example/myapp)")
	golangBuildCmd.Flags().BoolVarP(&golangWorkspace, "workspace", "w", false, "Enable workspace mode (generates go.work)")
	golangBuildCmd.Flags().BoolVarP(&golangVerbose, "verbose", "v", false, "Show detailed diagnostics")
	golangBuildCmd.Flags().BoolVar(&golangJSON, "json", false, "Output result as JSON")
	golangBuildCmd.Flags().BoolVar(&golangJSONL, "jsonl", false, "Output as JSONL (one JSON object per line)")
	golangBuildCmd.Flags().StringVar(&golangJSONLInput, "jsonl-input", "", "Path to JSONL file with batch inputs")
	golangBuildCmd.Flags().BoolVar(&golangWarningsAsErr, "warnings-as-errors", false, "Treat warnings as errors")

	// Add subcommands
	golangCmd.AddCommand(golangGenCmd)
	golangCmd.AddCommand(golangMakeCmd)
	golangCmd.AddCommand(golangBuildCmd)
}

func runGolangGen(cmd *cobra.Command, args []string) error {
	// Determine input IR path
	irPath := ""
	if len(args) > 0 {
		irPath = args[0]
	} else if golangIRFilePath != "" {
		irPath = golangIRFilePath
	}

	if irPath == "" {
		return fmt.Errorf("IR file path required (provide as argument or use -f flag)")
	}

	// Read and parse IR file
	module, err := loadMorphirIR(irPath)
	if err != nil {
		if golangJSON {
			return outputGolangGenJSON(cmd, nil, pipeline.StepResult{
				Err: err,
				Diagnostics: []pipeline.Diagnostic{
					{
						Severity: pipeline.SeverityError,
						Code:     "GOLANG001",
						Message:  fmt.Sprintf("failed to load IR: %v", err),
					},
				},
			})
		}
		return fmt.Errorf("failed to load IR file: %w", err)
	}

	// Resolve output directory to absolute path
	outputDir, err := filepath.Abs(golangOutputDir)
	if err != nil {
		return fmt.Errorf("failed to resolve output directory: %w", err)
	}

	// Create output directory if it doesn't exist
	if err := os.MkdirAll(outputDir, 0755); err != nil {
		return fmt.Errorf("failed to create output directory: %w", err)
	}

	// Create pipeline context
	mount := vfs.NewOSMount("workspace", vfs.MountRW, outputDir, vfs.MustVPath("/"))
	overlay := vfs.NewOverlayVFS([]vfs.Mount{mount})
	ctx := pipeline.NewContext(outputDir, 0, pipeline.ModeDefault, overlay)

	// Create and run gen step
	genStep := golangpipeline.NewGenStep()
	genInput := golangpipeline.GenInput{
		Module:    module,
		OutputDir: vfs.MustVPath("/"),
		Options: golangpipeline.GenOptions{
			ModulePath:       golangModulePath,
			Workspace:        golangWorkspace,
			WarningsAsErrors: golangWarningsAsErr,
			Format:           golangpipeline.DefaultFormatOptions(),
		},
	}

	output, result := genStep.Execute(ctx, genInput)

	// JSON output mode
	if golangJSON {
		return outputGolangGenJSON(cmd, &output, result)
	}

	// Output diagnostics (not in JSON mode)
	if golangVerbose || len(result.Diagnostics) > 0 {
		outputGolangDiagnostics(cmd, result.Diagnostics)
	}

	if result.Err != nil {
		return fmt.Errorf("generation failed: %w", result.Err)
	}

	// Write generated files to disk
	for relPath, content := range output.GeneratedFiles {
		fullPath := filepath.Join(outputDir, relPath)

		// Create parent directories
		parentDir := filepath.Dir(fullPath)
		if err := os.MkdirAll(parentDir, 0755); err != nil {
			return fmt.Errorf("failed to create directory %s: %w", parentDir, err)
		}

		// Write file
		if err := os.WriteFile(fullPath, []byte(content), 0644); err != nil {
			return fmt.Errorf("failed to write file %s: %w", fullPath, err)
		}
	}

	// Success message
	successStyle := lipgloss.NewStyle().Foreground(lipgloss.Color("10")).Bold(true)
	fmt.Fprintf(cmd.OutOrStdout(), "%s Generated Go code from Morphir IR\n", successStyle.Render("SUCCESS"))
	fmt.Fprintf(cmd.OutOrStdout(), "  Output directory: %s\n", outputDir)
	fmt.Fprintf(cmd.OutOrStdout(), "  Module path: %s\n", golangModulePath)
	fmt.Fprintf(cmd.OutOrStdout(), "  Files generated: %d\n", len(output.GeneratedFiles))

	// List generated files
	if golangVerbose {
		_, _ = fmt.Fprintln(cmd.OutOrStdout(), "\nGenerated files:")
		for relPath := range output.GeneratedFiles {
			_, _ = fmt.Fprintf(cmd.OutOrStdout(), "  - %s\n", relPath)
		}
	}

	return nil
}

// loadMorphirIR loads and parses a Morphir IR JSON file
func loadMorphirIR(path string) (ir.ModuleDefinition[any, any], error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return emptyModule(), fmt.Errorf("failed to read file: %w", err)
	}

	// Parse the JSON into our IR model
	// For now, we create a minimal module from the JSON structure
	var rawIR map[string]interface{}
	if err := json.Unmarshal(data, &rawIR); err != nil {
		return emptyModule(), fmt.Errorf("failed to parse JSON: %w", err)
	}

	// Check if this is a distribution format (has "distribution" key)
	if dist, ok := rawIR["distribution"]; ok {
		return parseDistributionIR(dist)
	}

	// Check if this is a module format directly
	if _, ok := rawIR["types"]; ok {
		return parseModuleIR(rawIR)
	}

	return emptyModule(), nil
}

// emptyModule creates an empty module definition
func emptyModule() ir.ModuleDefinition[any, any] {
	return ir.NewModuleDefinition[any, any](nil, nil, nil)
}

// parseDistributionIR parses a Morphir IR distribution format
func parseDistributionIR(_ interface{}) (ir.ModuleDefinition[any, any], error) {
	// The distribution format contains libraries with modules
	// For now, return a placeholder module
	// Full implementation would traverse the distribution structure
	return emptyModule(), nil
}

// parseModuleIR parses a direct module IR format
func parseModuleIR(_ map[string]interface{}) (ir.ModuleDefinition[any, any], error) {
	return emptyModule(), nil
}

// outputGolangGenJSON outputs the gen result as JSON
func outputGolangGenJSON(cmd *cobra.Command, output *golangpipeline.GenOutput, result pipeline.StepResult) error {
	jsonOutput := JSONGolangGenOutput{
		Success:     result.Err == nil,
		OutputDir:   golangOutputDir,
		ModulePath:  golangModulePath,
		Diagnostics: formatDiagnosticsJSON(result.Diagnostics),
	}

	if result.Err != nil {
		jsonOutput.Error = result.Err.Error()
	}

	if output != nil {
		jsonOutput.FileCount = len(output.GeneratedFiles)
		jsonOutput.GeneratedFiles = make([]string, 0, len(output.GeneratedFiles))
		for relPath := range output.GeneratedFiles {
			jsonOutput.GeneratedFiles = append(jsonOutput.GeneratedFiles, relPath)
		}
	}

	data, err := json.MarshalIndent(jsonOutput, "", "  ")
	if err != nil {
		return err
	}
	_, _ = fmt.Fprintln(cmd.OutOrStdout(), string(data))

	if result.Err != nil {
		return result.Err
	}
	return nil
}

// outputGolangDiagnostics prints diagnostics with color coding
func outputGolangDiagnostics(cmd *cobra.Command, diagnostics []pipeline.Diagnostic) {
	if len(diagnostics) == 0 {
		return
	}

	errorStyle := lipgloss.NewStyle().Foreground(lipgloss.Color("9")).Bold(true)
	warnStyle := lipgloss.NewStyle().Foreground(lipgloss.Color("11")).Bold(true)
	infoStyle := lipgloss.NewStyle().Foreground(lipgloss.Color("12"))
	dimStyle := lipgloss.NewStyle().Foreground(lipgloss.Color("8"))

	_, _ = fmt.Fprintln(cmd.ErrOrStderr(), "\nDiagnostics:")
	for _, d := range diagnostics {
		var prefix string
		switch d.Severity {
		case pipeline.SeverityError:
			prefix = errorStyle.Render("ERROR")
		case pipeline.SeverityWarn:
			prefix = warnStyle.Render("WARN")
		case pipeline.SeverityInfo:
			prefix = infoStyle.Render("INFO")
		default:
			prefix = dimStyle.Render("DEBUG")
		}

		code := ""
		if d.Code != "" {
			code = dimStyle.Render(fmt.Sprintf("[%s] ", d.Code))
		}

		fmt.Fprintf(cmd.ErrOrStderr(), "  %s %s%s\n", prefix, code, d.Message)
	}
	fmt.Fprintln(cmd.ErrOrStderr())
}

// runGolangMake executes the golang make command (placeholder)
func runGolangMake(cmd *cobra.Command, args []string) error {
	// Check for JSONL batch mode
	if golangJSONLInput != "" {
		return runGolangMakeBatch(cmd, args)
	}

	// Determine source path
	sourcePath := ""
	if len(args) > 0 {
		sourcePath = args[0]
	} else if golangSourcePath != "" {
		sourcePath = golangSourcePath
	}

	// Create pipeline context
	ctx := pipeline.NewContext(".", 0, pipeline.ModeDefault, nil)

	// Create and run make step
	makeStep := golangpipeline.NewMakeStep()
	makeInput := golangpipeline.MakeInput{
		Options: golangpipeline.MakeOptions{
			WarningsAsErrors: golangWarningsAsErr,
		},
	}
	// Only set FilePath if sourcePath is provided
	if sourcePath != "" {
		makeInput.FilePath = vfs.MustVPath(sourcePath)
	}

	_, result := makeStep.Execute(ctx, makeInput)

	// JSONL output mode
	if golangJSONL {
		return outputGolangMakeJSONL(cmd, "", sourcePath, result)
	}

	// JSON output mode
	if golangJSON {
		return outputGolangMakeJSON(cmd, sourcePath, result)
	}

	// Output diagnostics
	if golangVerbose || len(result.Diagnostics) > 0 {
		outputGolangDiagnostics(cmd, result.Diagnostics)
	}

	if result.Err != nil {
		return fmt.Errorf("make failed: %w", result.Err)
	}

	// Info message about not implemented
	warnStyle := lipgloss.NewStyle().Foreground(lipgloss.Color("11")).Bold(true)
	fmt.Fprintf(cmd.OutOrStdout(), "%s Go frontend (Go → Morphir IR) is not yet implemented\n", warnStyle.Render("INFO"))
	fmt.Fprintf(cmd.OutOrStdout(), "  This command is a placeholder for future functionality.\n")
	if sourcePath != "" {
		fmt.Fprintf(cmd.OutOrStdout(), "  Source path: %s\n", sourcePath)
	}

	return nil
}

// runGolangMakeBatch processes multiple Go sources from JSONL input
func runGolangMakeBatch(cmd *cobra.Command, _ []string) error {
	inputs, err := readGolangJSONLInputs(golangJSONLInput)
	if err != nil {
		return fmt.Errorf("failed to read JSONL input: %w", err)
	}

	// Create pipeline context
	ctx := pipeline.NewContext(".", 0, pipeline.ModeDefault, nil)

	makeStep := golangpipeline.NewMakeStep()
	var hasErrors bool

	for _, input := range inputs {
		makeInput := golangpipeline.MakeInput{
			Options: golangpipeline.MakeOptions{
				WarningsAsErrors: golangWarningsAsErr,
			},
		}
		if input.SourceFile != "" {
			makeInput.FilePath = vfs.MustVPath(input.SourceFile)
		}

		_, result := makeStep.Execute(ctx, makeInput)
		if err := outputGolangMakeJSONL(cmd, input.Name, input.SourceFile, result); err != nil {
			hasErrors = true
		}

		if result.Err != nil {
			hasErrors = true
		}
	}

	if hasErrors {
		return fmt.Errorf("one or more inputs failed")
	}
	return nil
}

// outputGolangMakeJSON outputs the make result as JSON
func outputGolangMakeJSON(cmd *cobra.Command, sourcePath string, result pipeline.StepResult) error {
	jsonOutput := JSONGolangMakeOutput{
		Success:     result.Err == nil,
		SourcePath:  sourcePath,
		Diagnostics: formatDiagnosticsJSON(result.Diagnostics),
	}

	if result.Err != nil {
		jsonOutput.Error = result.Err.Error()
	}

	data, err := json.MarshalIndent(jsonOutput, "", "  ")
	if err != nil {
		return err
	}
	fmt.Fprintln(cmd.OutOrStdout(), string(data))

	return nil
}

// runGolangBuild executes the golang build command
func runGolangBuild(cmd *cobra.Command, args []string) error {
	// Check for JSONL batch mode
	if golangJSONLInput != "" {
		return runGolangBuildBatch(cmd, args)
	}

	// Determine input IR path
	irPath := ""
	if len(args) > 0 {
		irPath = args[0]
	} else if golangIRFilePath != "" {
		irPath = golangIRFilePath
	}

	if irPath == "" {
		return fmt.Errorf("IR file path required (provide as argument or use -f flag)")
	}

	// Read and parse IR file
	module, err := loadMorphirIR(irPath)
	if err != nil {
		if golangJSON {
			return outputGolangBuildJSON(cmd, irPath, nil, pipeline.StepResult{
				Err: err,
				Diagnostics: []pipeline.Diagnostic{
					{
						Severity: pipeline.SeverityError,
						Code:     "GOLANG001",
						Message:  fmt.Sprintf("failed to load IR: %v", err),
					},
				},
			})
		}
		return fmt.Errorf("failed to load IR file: %w", err)
	}

	// Resolve output directory to absolute path
	outputDir, err := filepath.Abs(golangOutputDir)
	if err != nil {
		return fmt.Errorf("failed to resolve output directory: %w", err)
	}

	// Create output directory if it doesn't exist
	if err := os.MkdirAll(outputDir, 0755); err != nil {
		return fmt.Errorf("failed to create output directory: %w", err)
	}

	// Create pipeline context
	mount := vfs.NewOSMount("workspace", vfs.MountRW, outputDir, vfs.MustVPath("/"))
	overlay := vfs.NewOverlayVFS([]vfs.Mount{mount})
	ctx := pipeline.NewContext(outputDir, 0, pipeline.ModeDefault, overlay)

	// Create and run build step (which internally uses gen)
	buildStep := golangpipeline.NewBuildStep()
	buildInput := golangpipeline.BuildInput{
		IRPath:    vfs.MustVPath(irPath),
		OutputDir: vfs.MustVPath("/"),
		Options: golangpipeline.BuildOptions{
			GenOptions: golangpipeline.GenOptions{
				ModulePath:       golangModulePath,
				Workspace:        golangWorkspace,
				WarningsAsErrors: golangWarningsAsErr,
				Format:           golangpipeline.DefaultFormatOptions(),
			},
		},
	}

	buildOutput, buildResult := buildStep.Execute(ctx, buildInput)

	// Since build step is a stub, run gen directly for actual file generation
	genStep := golangpipeline.NewGenStep()
	genInput := golangpipeline.GenInput{
		Module:    module,
		OutputDir: vfs.MustVPath("/"),
		Options: golangpipeline.GenOptions{
			ModulePath:       golangModulePath,
			Workspace:        golangWorkspace,
			WarningsAsErrors: golangWarningsAsErr,
			Format:           golangpipeline.DefaultFormatOptions(),
		},
	}

	genOutput, genResult := genStep.Execute(ctx, genInput)

	// Combine diagnostics from both steps
	allDiagnostics := append(buildResult.Diagnostics, genResult.Diagnostics...)

	// JSONL output mode
	if golangJSONL {
		return outputGolangBuildJSONL(cmd, "", irPath, outputDir, &genOutput, pipeline.StepResult{
			Err:         genResult.Err,
			Diagnostics: allDiagnostics,
		})
	}

	// JSON output mode
	if golangJSON {
		return outputGolangBuildJSON(cmd, irPath, &genOutput, pipeline.StepResult{
			Err:         genResult.Err,
			Diagnostics: allDiagnostics,
		})
	}

	// Output diagnostics
	if golangVerbose || len(allDiagnostics) > 0 {
		outputGolangDiagnostics(cmd, allDiagnostics)
	}

	if genResult.Err != nil {
		return fmt.Errorf("build failed: %w", genResult.Err)
	}

	// Write generated files to disk
	for relPath, content := range genOutput.GeneratedFiles {
		fullPath := filepath.Join(outputDir, relPath)

		// Create parent directories
		parentDir := filepath.Dir(fullPath)
		if err := os.MkdirAll(parentDir, 0755); err != nil {
			return fmt.Errorf("failed to create directory %s: %w", parentDir, err)
		}

		// Write file
		if err := os.WriteFile(fullPath, []byte(content), 0644); err != nil {
			return fmt.Errorf("failed to write file %s: %w", fullPath, err)
		}
	}

	// Success message
	successStyle := lipgloss.NewStyle().Foreground(lipgloss.Color("10")).Bold(true)
	fmt.Fprintf(cmd.OutOrStdout(), "%s Built Go code from Morphir IR\n", successStyle.Render("SUCCESS"))
	fmt.Fprintf(cmd.OutOrStdout(), "  IR file: %s\n", irPath)
	fmt.Fprintf(cmd.OutOrStdout(), "  Output directory: %s\n", outputDir)
	fmt.Fprintf(cmd.OutOrStdout(), "  Module path: %s\n", golangModulePath)
	fmt.Fprintf(cmd.OutOrStdout(), "  Files generated: %d\n", len(genOutput.GeneratedFiles))

	// Note about stub implementation
	_ = buildOutput // Acknowledge we're not using full build output yet

	// List generated files
	if golangVerbose {
		fmt.Fprintln(cmd.OutOrStdout(), "\nGenerated files:")
		for relPath := range genOutput.GeneratedFiles {
			fmt.Fprintf(cmd.OutOrStdout(), "  - %s\n", relPath)
		}
	}

	return nil
}

// outputGolangBuildJSON outputs the build result as JSON
func outputGolangBuildJSON(cmd *cobra.Command, irPath string, output *golangpipeline.GenOutput, result pipeline.StepResult) error {
	jsonOutput := JSONGolangBuildOutput{
		Success:     result.Err == nil,
		IRPath:      irPath,
		OutputDir:   golangOutputDir,
		ModulePath:  golangModulePath,
		Diagnostics: formatDiagnosticsJSON(result.Diagnostics),
	}

	if result.Err != nil {
		jsonOutput.Error = result.Err.Error()
	}

	if output != nil {
		jsonOutput.FileCount = len(output.GeneratedFiles)
		jsonOutput.GeneratedFiles = make([]string, 0, len(output.GeneratedFiles))
		for relPath := range output.GeneratedFiles {
			jsonOutput.GeneratedFiles = append(jsonOutput.GeneratedFiles, relPath)
		}
	}

	data, err := json.MarshalIndent(jsonOutput, "", "  ")
	if err != nil {
		return err
	}
	fmt.Fprintln(cmd.OutOrStdout(), string(data))

	if result.Err != nil {
		return result.Err
	}
	return nil
}

// runGolangBuildBatch processes multiple IR files from JSONL input
func runGolangBuildBatch(cmd *cobra.Command, _ []string) error {
	inputs, err := readGolangJSONLInputs(golangJSONLInput)
	if err != nil {
		return fmt.Errorf("failed to read JSONL input: %w", err)
	}

	var hasErrors bool

	for _, input := range inputs {
		// Determine IR path
		irPath := input.IRFile
		if irPath == "" {
			if err := outputGolangBuildJSONLError(cmd, input.Name, "", "", fmt.Errorf("irFile is required")); err != nil {
				hasErrors = true
			}
			continue
		}

		// Determine output directory
		outputDir := input.OutputDir
		if outputDir == "" {
			outputDir = golangOutputDir
		}
		if outputDir == "" {
			if err := outputGolangBuildJSONLError(cmd, input.Name, irPath, "", fmt.Errorf("outputDir is required")); err != nil {
				hasErrors = true
			}
			continue
		}

		// Determine module path
		modulePath := input.ModulePath
		if modulePath == "" {
			modulePath = golangModulePath
		}
		if modulePath == "" {
			if err := outputGolangBuildJSONLError(cmd, input.Name, irPath, outputDir, fmt.Errorf("modulePath is required")); err != nil {
				hasErrors = true
			}
			continue
		}

		// Read and parse IR file
		module, err := loadMorphirIR(irPath)
		if err != nil {
			if err := outputGolangBuildJSONLError(cmd, input.Name, irPath, outputDir, err); err != nil {
				hasErrors = true
			}
			continue
		}

		// Resolve output directory to absolute path
		absOutputDir, err := filepath.Abs(outputDir)
		if err != nil {
			if err := outputGolangBuildJSONLError(cmd, input.Name, irPath, outputDir, err); err != nil {
				hasErrors = true
			}
			continue
		}

		// Create output directory if it doesn't exist
		if err := os.MkdirAll(absOutputDir, 0755); err != nil {
			if err := outputGolangBuildJSONLError(cmd, input.Name, irPath, absOutputDir, err); err != nil {
				hasErrors = true
			}
			continue
		}

		// Create pipeline context
		mount := vfs.NewOSMount("workspace", vfs.MountRW, absOutputDir, vfs.MustVPath("/"))
		overlay := vfs.NewOverlayVFS([]vfs.Mount{mount})
		ctx := pipeline.NewContext(absOutputDir, 0, pipeline.ModeDefault, overlay)

		// Create and run gen step
		genStep := golangpipeline.NewGenStep()
		genInput := golangpipeline.GenInput{
			Module:    module,
			OutputDir: vfs.MustVPath("/"),
			Options: golangpipeline.GenOptions{
				ModulePath:       modulePath,
				Workspace:        golangWorkspace,
				WarningsAsErrors: golangWarningsAsErr,
				Format:           golangpipeline.DefaultFormatOptions(),
			},
		}

		genOutput, genResult := genStep.Execute(ctx, genInput)

		// Write generated files to disk
		if genResult.Err == nil {
			for relPath, content := range genOutput.GeneratedFiles {
				fullPath := filepath.Join(absOutputDir, relPath)

				// Create parent directories
				parentDir := filepath.Dir(fullPath)
				if mkErr := os.MkdirAll(parentDir, 0755); mkErr != nil {
					genResult.Err = mkErr
					break
				}

				// Write file
				if writeErr := os.WriteFile(fullPath, []byte(content), 0644); writeErr != nil {
					genResult.Err = writeErr
					break
				}
			}
		}

		if err := outputGolangBuildJSONL(cmd, input.Name, irPath, absOutputDir, &genOutput, genResult); err != nil {
			hasErrors = true
		}

		if genResult.Err != nil {
			hasErrors = true
		}
	}

	if hasErrors {
		return fmt.Errorf("one or more inputs failed")
	}
	return nil
}

// readGolangJSONLInputs reads a JSONL file and returns a slice of inputs
func readGolangJSONLInputs(path string) ([]JSONLGolangInput, error) {
	var file io.Reader

	if path == "-" {
		file = os.Stdin
	} else {
		f, err := os.Open(path)
		if err != nil {
			return nil, fmt.Errorf("failed to open file: %w", err)
		}
		defer func() { _ = f.Close() }()
		file = f
	}

	var inputs []JSONLGolangInput
	scanner := bufio.NewScanner(file)

	lineNum := 0
	for scanner.Scan() {
		lineNum++
		line := strings.TrimSpace(scanner.Text())
		if line == "" || strings.HasPrefix(line, "#") {
			continue // Skip empty lines and comments
		}

		var input JSONLGolangInput
		if err := json.Unmarshal([]byte(line), &input); err != nil {
			return nil, fmt.Errorf("failed to parse line %d: %w", lineNum, err)
		}
		inputs = append(inputs, input)
	}

	if err := scanner.Err(); err != nil {
		return nil, fmt.Errorf("failed to read file: %w", err)
	}

	return inputs, nil
}

// outputGolangMakeJSONL outputs a single make result as a JSONL line
func outputGolangMakeJSONL(cmd *cobra.Command, name, sourcePath string, result pipeline.StepResult) error {
	output := JSONLGolangMakeOutput{
		Name:        name,
		Success:     result.Err == nil,
		SourcePath:  sourcePath,
		Diagnostics: formatDiagnosticsJSON(result.Diagnostics),
	}

	if result.Err != nil {
		output.Error = result.Err.Error()
	}

	return writeGolangJSONL(cmd.OutOrStdout(), output)
}

// outputGolangBuildJSONL outputs a single build result as a JSONL line
func outputGolangBuildJSONL(cmd *cobra.Command, name, irPath, outputDir string, genOutput *golangpipeline.GenOutput, result pipeline.StepResult) error {
	output := JSONLGolangBuildOutput{
		Name:        name,
		Success:     result.Err == nil,
		IRPath:      irPath,
		OutputDir:   outputDir,
		ModulePath:  golangModulePath,
		Diagnostics: formatDiagnosticsJSON(result.Diagnostics),
	}

	if result.Err != nil {
		output.Error = result.Err.Error()
	}

	if genOutput != nil {
		output.FileCount = len(genOutput.GeneratedFiles)
		output.GeneratedFiles = make([]string, 0, len(genOutput.GeneratedFiles))
		for relPath := range genOutput.GeneratedFiles {
			output.GeneratedFiles = append(output.GeneratedFiles, relPath)
		}
	}

	return writeGolangJSONL(cmd.OutOrStdout(), output)
}

// outputGolangBuildJSONLError outputs a build error as a JSONL line
func outputGolangBuildJSONLError(cmd *cobra.Command, name, irPath, outputDir string, err error) error {
	output := JSONLGolangBuildOutput{
		Name:      name,
		Success:   false,
		IRPath:    irPath,
		OutputDir: outputDir,
		Error:     err.Error(),
	}

	return writeGolangJSONL(cmd.OutOrStdout(), output)
}

// writeGolangJSONL writes a value as a single JSONL line
func writeGolangJSONL(w io.Writer, v interface{}) error {
	data, err := json.Marshal(v)
	if err != nil {
		return err
	}
	_, err = fmt.Fprintln(w, string(data))
	return err
}
