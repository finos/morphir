package cmd

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"

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

var golangCmd = &cobra.Command{
	Use:   "golang",
	Short: "Go code generation operations",
	Long: `Commands for working with Go code generation from Morphir IR.

These commands convert Morphir IR to idiomatic Go code,
generating Go modules, packages, and workspace files.

Available Commands:
  gen    - Generate Go code from Morphir IR`,
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

func init() {
	// Gen command flags
	golangGenCmd.Flags().StringVarP(&golangIRFilePath, "file", "f", "", "Path to Morphir IR JSON file")
	golangGenCmd.Flags().StringVarP(&golangOutputDir, "output", "o", "", "Output directory for generated Go code")
	golangGenCmd.Flags().StringVarP(&golangModulePath, "module-path", "m", "", "Go module path (e.g., github.com/example/myapp)")
	golangGenCmd.Flags().BoolVarP(&golangWorkspace, "workspace", "w", false, "Enable workspace mode (generates go.work)")
	golangGenCmd.Flags().BoolVarP(&golangVerbose, "verbose", "v", false, "Show detailed diagnostics")
	golangGenCmd.Flags().BoolVar(&golangJSON, "json", false, "Output result as JSON")
	golangGenCmd.Flags().BoolVar(&golangWarningsAsErr, "warnings-as-errors", false, "Treat warnings as errors")

	// Mark required flags
	_ = golangGenCmd.MarkFlagRequired("output")
	_ = golangGenCmd.MarkFlagRequired("module-path")

	// Add subcommands
	golangCmd.AddCommand(golangGenCmd)
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
		fmt.Fprintln(cmd.OutOrStdout(), "\nGenerated files:")
		for relPath := range output.GeneratedFiles {
			fmt.Fprintf(cmd.OutOrStdout(), "  - %s\n", relPath)
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
	fmt.Fprintln(cmd.OutOrStdout(), string(data))

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

	fmt.Fprintln(cmd.ErrOrStderr(), "\nDiagnostics:")
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
