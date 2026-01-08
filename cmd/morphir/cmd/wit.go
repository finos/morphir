package cmd

import (
	"encoding/json"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"

	"github.com/charmbracelet/lipgloss"
	witpipeline "github.com/finos/morphir/pkg/bindings/wit/pipeline"
	"github.com/finos/morphir/pkg/pipeline"
	"github.com/finos/morphir/pkg/vfs"
	"github.com/spf13/cobra"
)

// WIT command flags
var (
	witSource           string
	witFilePath         string
	witOutputPath       string
	witWarningsAsErrors bool
	witStrictMode       bool
	witJSON             bool
	witVerbose          bool
)

var witCmd = &cobra.Command{
	Use:   "wit",
	Short: "WIT (WebAssembly Interface Types) operations",
	Long: `Commands for working with WIT (WebAssembly Interface Types).

WIT is the interface definition language for WebAssembly components.
These commands convert between WIT and Morphir IR.

Available Commands:
  make   - Compile WIT to Morphir IR (frontend)
  gen    - Generate WIT from Morphir IR (backend)
  build  - Full pipeline: WIT -> IR -> WIT with round-trip validation`,
}

var witMakeCmd = &cobra.Command{
	Use:   "make [file.wit]",
	Short: "Compile WIT to Morphir IR",
	Long: `Compile a WIT file to Morphir IR.

This is the frontend compilation step that parses WIT and converts it
to Morphir's intermediate representation.

Examples:
  morphir wit make example.wit -o example.ir.json
  morphir wit make -s "interface foo { bar: func(); }" -o out.ir.json
  cat example.wit | morphir wit make -o out.ir.json`,
	Args: cobra.MaximumNArgs(1),
	RunE: runWitMake,
}

var witGenCmd = &cobra.Command{
	Use:   "gen [file.ir.json]",
	Short: "Generate WIT from Morphir IR",
	Long: `Generate WIT source code from Morphir IR.

This is the backend generation step that converts Morphir IR
to WIT source code.

Examples:
  morphir wit gen example.ir.json -o example.wit
  morphir wit gen -f example.ir.json -o example.wit`,
	Args: cobra.MaximumNArgs(1),
	RunE: runWitGen,
}

var witBuildCmd = &cobra.Command{
	Use:   "build [file.wit]",
	Short: "Full WIT build pipeline (make + gen)",
	Long: `Run the full WIT build pipeline: WIT -> IR -> WIT.

This combines the make and gen steps with round-trip validation
to verify that the conversion is semantically correct.

Examples:
  morphir wit build example.wit -o regenerated.wit
  morphir wit build -s "interface foo { bar: func(); }" -o out.wit`,
	Args: cobra.MaximumNArgs(1),
	RunE: runWitBuild,
}

func init() {
	// Make command flags
	witMakeCmd.Flags().StringVarP(&witSource, "source", "s", "", "WIT source code (inline)")
	witMakeCmd.Flags().StringVarP(&witFilePath, "file", "f", "", "Path to WIT file")
	witMakeCmd.Flags().StringVarP(&witOutputPath, "output", "o", "", "Output path for IR JSON")
	witMakeCmd.Flags().BoolVar(&witWarningsAsErrors, "warnings-as-errors", false, "Treat warnings as errors")
	witMakeCmd.Flags().BoolVar(&witStrictMode, "strict", false, "Fail on unsupported constructs")
	witMakeCmd.Flags().BoolVar(&witJSON, "json", false, "Output result as JSON")
	witMakeCmd.Flags().BoolVarP(&witVerbose, "verbose", "v", false, "Show detailed diagnostics")

	// Gen command flags
	witGenCmd.Flags().StringVarP(&witFilePath, "file", "f", "", "Path to IR JSON file")
	witGenCmd.Flags().StringVarP(&witOutputPath, "output", "o", "", "Output path for WIT file")
	witGenCmd.Flags().BoolVar(&witWarningsAsErrors, "warnings-as-errors", false, "Treat warnings as errors")
	witGenCmd.Flags().BoolVar(&witJSON, "json", false, "Output result as JSON")
	witGenCmd.Flags().BoolVarP(&witVerbose, "verbose", "v", false, "Show detailed diagnostics")

	// Build command flags
	witBuildCmd.Flags().StringVarP(&witSource, "source", "s", "", "WIT source code (inline)")
	witBuildCmd.Flags().StringVarP(&witFilePath, "file", "f", "", "Path to WIT file")
	witBuildCmd.Flags().StringVarP(&witOutputPath, "output", "o", "", "Output path for regenerated WIT")
	witBuildCmd.Flags().BoolVar(&witWarningsAsErrors, "warnings-as-errors", false, "Treat warnings as errors")
	witBuildCmd.Flags().BoolVar(&witStrictMode, "strict", false, "Fail on unsupported constructs")
	witBuildCmd.Flags().BoolVar(&witJSON, "json", false, "Output result as JSON")
	witBuildCmd.Flags().BoolVarP(&witVerbose, "verbose", "v", false, "Show detailed diagnostics")

	// Add subcommands
	witCmd.AddCommand(witMakeCmd)
	witCmd.AddCommand(witGenCmd)
	witCmd.AddCommand(witBuildCmd)
}

func runWitMake(cmd *cobra.Command, args []string) error {
	// Determine source
	source, inputPath, err := resolveWitSource(args)
	if err != nil {
		return err
	}

	// Create pipeline context
	workDir, _ := os.Getwd()
	mount := vfs.NewOSMount("workspace", vfs.MountRW, workDir, vfs.MustVPath("/"))
	overlay := vfs.NewOverlayVFS([]vfs.Mount{mount})
	ctx := pipeline.NewContext(workDir, 0, pipeline.ModeDefault, overlay)

	// Create and run make step
	makeStep := witpipeline.NewMakeStep()
	makeInput := witpipeline.MakeInput{
		Source: source,
		Options: witpipeline.MakeOptions{
			WarningsAsErrors: witWarningsAsErrors,
			StrictMode:       witStrictMode,
		},
	}

	if inputPath != "" && source == "" {
		makeInput.FilePath = vfs.MustVPath("/" + filepath.Base(inputPath))
	}

	output, result := makeStep.Execute(ctx, makeInput)

	// Output diagnostics
	if witVerbose || len(result.Diagnostics) > 0 {
		outputDiagnostics(cmd, result.Diagnostics)
	}

	if result.Err != nil {
		return fmt.Errorf("make failed: %w", result.Err)
	}

	// Output result
	if witJSON {
		return outputMakeJSON(cmd, output, result)
	}

	// Write IR if output path specified
	if witOutputPath != "" {
		irJSON, err := json.MarshalIndent(output.Module, "", "  ")
		if err != nil {
			return fmt.Errorf("failed to marshal IR: %w", err)
		}
		if err := os.WriteFile(witOutputPath, irJSON, 0644); err != nil {
			return fmt.Errorf("failed to write IR: %w", err)
		}
		fmt.Fprintf(cmd.OutOrStdout(), "Wrote IR to %s\n", witOutputPath)
	}

	// Success message
	successStyle := lipgloss.NewStyle().Foreground(lipgloss.Color("10")).Bold(true)
	fmt.Fprintf(cmd.OutOrStdout(), "%s Compiled WIT to Morphir IR\n", successStyle.Render("SUCCESS"))
	fmt.Fprintf(cmd.OutOrStdout(), "  Types: %d, Values: %d\n",
		len(output.Module.Types()), len(output.Module.Values()))

	return nil
}

func runWitGen(cmd *cobra.Command, args []string) error {
	// Determine input IR path
	inputPath := ""
	if len(args) > 0 {
		inputPath = args[0]
	} else if witFilePath != "" {
		inputPath = witFilePath
	}

	if inputPath == "" {
		return fmt.Errorf("IR file path required (provide as argument or use -f flag)")
	}

	// Read IR file
	irData, err := os.ReadFile(inputPath)
	if err != nil {
		return fmt.Errorf("failed to read IR file: %w", err)
	}

	// Parse IR into module (simplified - in practice would use proper IR parsing)
	// For now, we'll parse the WIT from the source package if available
	// This is a placeholder - real implementation would deserialize IR JSON
	_ = irData

	// For demonstration, show that gen step exists
	// Full implementation would parse IR JSON and run the gen step
	fmt.Fprintf(cmd.ErrOrStderr(), "Note: Full IR JSON parsing not yet implemented.\n")
	fmt.Fprintf(cmd.ErrOrStderr(), "The gen step exists in pkg/bindings/wit/pipeline/gen.go\n")

	return fmt.Errorf("IR JSON parsing not yet implemented - use build command for round-trip")
}

func runWitBuild(cmd *cobra.Command, args []string) error {
	// Determine source
	source, inputPath, err := resolveWitSource(args)
	if err != nil {
		return err
	}

	// Create pipeline context
	workDir, _ := os.Getwd()
	mount := vfs.NewOSMount("workspace", vfs.MountRW, workDir, vfs.MustVPath("/"))
	overlay := vfs.NewOverlayVFS([]vfs.Mount{mount})
	ctx := pipeline.NewContext(workDir, 0, pipeline.ModeDefault, overlay)

	// Create output VPath if specified
	var outputVPath vfs.VPath
	if witOutputPath != "" {
		outputVPath = vfs.MustVPath("/" + filepath.Base(witOutputPath))
	}

	// Create and run build step
	buildStep := witpipeline.NewBuildStep()
	buildInput := witpipeline.BuildInput{
		Source:     source,
		OutputPath: outputVPath,
		MakeOptions: witpipeline.MakeOptions{
			WarningsAsErrors: witWarningsAsErrors,
			StrictMode:       witStrictMode,
		},
		GenOptions: witpipeline.GenOptions{
			WarningsAsErrors: witWarningsAsErrors,
		},
	}

	if inputPath != "" && source == "" {
		buildInput.FilePath = vfs.MustVPath("/" + filepath.Base(inputPath))
	}

	output, result := buildStep.Execute(ctx, buildInput)

	// Output diagnostics
	if witVerbose || len(result.Diagnostics) > 0 {
		outputDiagnostics(cmd, result.Diagnostics)
	}

	if result.Err != nil {
		return fmt.Errorf("build failed: %w", result.Err)
	}

	// Output result
	if witJSON {
		return outputBuildJSON(cmd, output, result)
	}

	// Write WIT if output path specified
	if witOutputPath != "" {
		if err := os.WriteFile(witOutputPath, []byte(output.Gen.Source), 0644); err != nil {
			return fmt.Errorf("failed to write WIT: %w", err)
		}
		fmt.Fprintf(cmd.OutOrStdout(), "Wrote WIT to %s\n", witOutputPath)
	} else {
		// Print generated WIT to stdout
		fmt.Fprintln(cmd.OutOrStdout(), output.Gen.Source)
	}

	// Success/validation message
	if output.RoundTripValid {
		successStyle := lipgloss.NewStyle().Foreground(lipgloss.Color("10")).Bold(true)
		fmt.Fprintf(cmd.OutOrStdout(), "%s Round-trip validation passed\n", successStyle.Render("VALID"))
	} else {
		warnStyle := lipgloss.NewStyle().Foreground(lipgloss.Color("11")).Bold(true)
		fmt.Fprintf(cmd.OutOrStdout(), "%s Round-trip produced different output (lossy conversion)\n", warnStyle.Render("WARN"))
	}

	return nil
}

// resolveWitSource determines the WIT source from args, flags, or stdin
func resolveWitSource(args []string) (source string, inputPath string, err error) {
	// Check for inline source
	if witSource != "" {
		return witSource, "", nil
	}

	// Check for file path from args or flag
	if len(args) > 0 {
		inputPath = args[0]
	} else if witFilePath != "" {
		inputPath = witFilePath
	}

	if inputPath != "" {
		data, err := os.ReadFile(inputPath)
		if err != nil {
			return "", "", fmt.Errorf("failed to read WIT file: %w", err)
		}
		return string(data), inputPath, nil
	}

	// Check for stdin
	stat, _ := os.Stdin.Stat()
	if (stat.Mode() & os.ModeCharDevice) == 0 {
		data, err := io.ReadAll(os.Stdin)
		if err != nil {
			return "", "", fmt.Errorf("failed to read from stdin: %w", err)
		}
		return string(data), "", nil
	}

	return "", "", fmt.Errorf("WIT source required (provide file, use -s flag, or pipe to stdin)")
}

// outputDiagnostics prints diagnostics with color coding
func outputDiagnostics(cmd *cobra.Command, diagnostics []pipeline.Diagnostic) {
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

// outputMakeJSON outputs make result as JSON
func outputMakeJSON(cmd *cobra.Command, output witpipeline.MakeOutput, result pipeline.StepResult) error {
	jsonResult := map[string]interface{}{
		"success":     result.Err == nil,
		"typeCount":   len(output.Module.Types()),
		"valueCount":  len(output.Module.Values()),
		"diagnostics": formatDiagnosticsJSON(result.Diagnostics),
	}

	if result.Err != nil {
		jsonResult["error"] = result.Err.Error()
	}

	data, err := json.MarshalIndent(jsonResult, "", "  ")
	if err != nil {
		return err
	}
	fmt.Fprintln(cmd.OutOrStdout(), string(data))
	return nil
}

// outputBuildJSON outputs build result as JSON
func outputBuildJSON(cmd *cobra.Command, output witpipeline.BuildOutput, result pipeline.StepResult) error {
	jsonResult := map[string]interface{}{
		"success":        result.Err == nil,
		"roundTripValid": output.RoundTripValid,
		"typeCount":      len(output.Make.Module.Types()),
		"valueCount":     len(output.Make.Module.Values()),
		"diagnostics":    formatDiagnosticsJSON(result.Diagnostics),
	}

	if result.Err != nil {
		jsonResult["error"] = result.Err.Error()
	}

	if output.Gen.Source != "" {
		jsonResult["witSource"] = output.Gen.Source
	}

	data, err := json.MarshalIndent(jsonResult, "", "  ")
	if err != nil {
		return err
	}
	fmt.Fprintln(cmd.OutOrStdout(), string(data))
	return nil
}

// formatDiagnosticsJSON converts diagnostics to JSON-friendly format
func formatDiagnosticsJSON(diagnostics []pipeline.Diagnostic) []map[string]string {
	result := make([]map[string]string, len(diagnostics))
	for i, d := range diagnostics {
		result[i] = map[string]string{
			"severity": strings.ToLower(string(d.Severity)),
			"code":     d.Code,
			"message":  d.Message,
		}
	}
	return result
}
