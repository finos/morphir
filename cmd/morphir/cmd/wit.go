package cmd

import (
	"bufio"
	"encoding/json"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"

	"github.com/charmbracelet/lipgloss/v2"
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
	witJSONL            bool   // JSONL output mode (one JSON object per line)
	witJSONLInput       string // Path to JSONL input file for batch processing
	witVerbose          bool
)

// JSONLInput represents a single input in JSONL batch mode
type JSONLInput struct {
	// Name is an optional identifier for this input (used in output)
	Name string `json:"name,omitempty"`
	// Source is inline WIT source code
	Source string `json:"source,omitempty"`
	// File is a path to a WIT file
	File string `json:"file,omitempty"`
}

// JSONLMakeOutput represents a single make result in JSONL output mode
type JSONLMakeOutput struct {
	Name        string              `json:"name,omitempty"`
	Success     bool                `json:"success"`
	TypeCount   int                 `json:"typeCount,omitempty"`
	ValueCount  int                 `json:"valueCount,omitempty"`
	Module      any                 `json:"module,omitempty"`
	Error       string              `json:"error,omitempty"`
	Diagnostics []map[string]string `json:"diagnostics,omitempty"`
}

// JSONLBuildOutput represents a single build result in JSONL output mode
type JSONLBuildOutput struct {
	Name           string              `json:"name,omitempty"`
	Success        bool                `json:"success"`
	RoundTripValid bool                `json:"roundTripValid,omitempty"`
	TypeCount      int                 `json:"typeCount,omitempty"`
	ValueCount     int                 `json:"valueCount,omitempty"`
	Module         any                 `json:"module,omitempty"`
	WITSource      string              `json:"witSource,omitempty"`
	Error          string              `json:"error,omitempty"`
	Diagnostics    []map[string]string `json:"diagnostics,omitempty"`
}

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
  cat example.wit | morphir wit make -o out.ir.json

JSONL Batch Mode:
  Process multiple WIT sources from a JSONL file (one JSON object per line):

  morphir wit make --jsonl-input sources.jsonl --jsonl

  Input format (each line):
    {"name": "foo", "source": "package a:b; interface foo { ... }"}
    {"name": "bar", "file": "path/to/bar.wit"}

  Output format (--jsonl):
    {"name": "foo", "success": true, "typeCount": 2, "valueCount": 1}
    {"name": "bar", "success": false, "error": "parse error..."}`,
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
  morphir wit build -s "interface foo { bar: func(); }" -o out.wit

JSONL Batch Mode:
  Process multiple WIT sources from a JSONL file:

  morphir wit build --jsonl-input sources.jsonl --jsonl

  Input format (each line):
    {"name": "foo", "source": "package a:b; interface foo { ... }"}
    {"name": "bar", "file": "path/to/bar.wit"}

  Output format (--jsonl):
    {"name": "foo", "success": true, "roundTripValid": true, "witSource": "..."}`,
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
	witMakeCmd.Flags().BoolVar(&witJSON, "json", false, "Output result as JSON (pretty-printed)")
	witMakeCmd.Flags().BoolVar(&witJSONL, "jsonl", false, "Output as JSONL (one JSON object per line)")
	witMakeCmd.Flags().StringVar(&witJSONLInput, "jsonl-input", "", "Path to JSONL file with batch inputs")
	witMakeCmd.Flags().BoolVarP(&witVerbose, "verbose", "v", false, "Show detailed diagnostics")

	// Gen command flags
	witGenCmd.Flags().StringVarP(&witFilePath, "file", "f", "", "Path to IR JSON file")
	witGenCmd.Flags().StringVarP(&witOutputPath, "output", "o", "", "Output path for WIT file")
	witGenCmd.Flags().BoolVar(&witWarningsAsErrors, "warnings-as-errors", false, "Treat warnings as errors")
	witGenCmd.Flags().BoolVar(&witJSON, "json", false, "Output result as JSON (pretty-printed)")
	witGenCmd.Flags().BoolVar(&witJSONL, "jsonl", false, "Output as JSONL (one JSON object per line)")
	witGenCmd.Flags().BoolVarP(&witVerbose, "verbose", "v", false, "Show detailed diagnostics")

	// Build command flags
	witBuildCmd.Flags().StringVarP(&witSource, "source", "s", "", "WIT source code (inline)")
	witBuildCmd.Flags().StringVarP(&witFilePath, "file", "f", "", "Path to WIT file")
	witBuildCmd.Flags().StringVarP(&witOutputPath, "output", "o", "", "Output path for regenerated WIT")
	witBuildCmd.Flags().BoolVar(&witWarningsAsErrors, "warnings-as-errors", false, "Treat warnings as errors")
	witBuildCmd.Flags().BoolVar(&witStrictMode, "strict", false, "Fail on unsupported constructs")
	witBuildCmd.Flags().BoolVar(&witJSON, "json", false, "Output result as JSON (pretty-printed)")
	witBuildCmd.Flags().BoolVar(&witJSONL, "jsonl", false, "Output as JSONL (one JSON object per line)")
	witBuildCmd.Flags().StringVar(&witJSONLInput, "jsonl-input", "", "Path to JSONL file with batch inputs")
	witBuildCmd.Flags().BoolVarP(&witVerbose, "verbose", "v", false, "Show detailed diagnostics")

	// Add subcommands
	witCmd.AddCommand(witMakeCmd)
	witCmd.AddCommand(witGenCmd)
	witCmd.AddCommand(witBuildCmd)
}

func runWitMake(cmd *cobra.Command, args []string) error {
	// Check for JSONL batch mode
	if witJSONLInput != "" {
		return runWitMakeBatch(cmd, args)
	}

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

	// JSONL output mode
	if witJSONL {
		return outputMakeJSONL(cmd, "", output, result)
	}

	// Output diagnostics (not in JSONL mode)
	if witVerbose || len(result.Diagnostics) > 0 {
		outputDiagnostics(cmd, result.Diagnostics)
	}

	if result.Err != nil {
		return fmt.Errorf("make failed: %w", result.Err)
	}

	// Output result as pretty JSON
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
		_, _ = fmt.Fprintf(cmd.OutOrStdout(), "Wrote IR to %s\n", witOutputPath)
	}

	// Success message
	successStyle := lipgloss.NewStyle().Foreground(lipgloss.Color("10")).Bold(true)
	_, _ = fmt.Fprintf(cmd.OutOrStdout(), "%s Compiled WIT to Morphir IR\n", successStyle.Render("SUCCESS"))
	_, _ = fmt.Fprintf(cmd.OutOrStdout(), "  Types: %d, Values: %d\n",
		len(output.Module.Types()), len(output.Module.Values()))

	return nil
}

// runWitMakeBatch processes multiple WIT sources from JSONL input
func runWitMakeBatch(cmd *cobra.Command, _ []string) error {
	inputs, err := readJSONLInputs(witJSONLInput)
	if err != nil {
		return fmt.Errorf("failed to read JSONL input: %w", err)
	}

	// Create pipeline context
	workDir, _ := os.Getwd()
	mount := vfs.NewOSMount("workspace", vfs.MountRW, workDir, vfs.MustVPath("/"))
	overlay := vfs.NewOverlayVFS([]vfs.Mount{mount})
	ctx := pipeline.NewContext(workDir, 0, pipeline.ModeDefault, overlay)

	makeStep := witpipeline.NewMakeStep()
	var hasErrors bool

	for _, input := range inputs {
		// Resolve source for this input
		source, err := resolveJSONLInputSource(input)
		if err != nil {
			// Output error as JSONL
			outputMakeJSONLError(cmd, input.Name, err)
			hasErrors = true
			continue
		}

		makeInput := witpipeline.MakeInput{
			Source: source,
			Options: witpipeline.MakeOptions{
				WarningsAsErrors: witWarningsAsErrors,
				StrictMode:       witStrictMode,
			},
		}

		output, result := makeStep.Execute(ctx, makeInput)
		if err := outputMakeJSONL(cmd, input.Name, output, result); err != nil {
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
	_, _ = fmt.Fprintf(cmd.ErrOrStderr(), "Note: Full IR JSON parsing not yet implemented.\n")
	_, _ = fmt.Fprintf(cmd.ErrOrStderr(), "The gen step exists in pkg/bindings/wit/pipeline/gen.go\n")

	return fmt.Errorf("IR JSON parsing not yet implemented - use build command for round-trip")
}

func runWitBuild(cmd *cobra.Command, args []string) error {
	// Check for JSONL batch mode
	if witJSONLInput != "" {
		return runWitBuildBatch(cmd, args)
	}

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

	// JSONL output mode
	if witJSONL {
		return outputBuildJSONL(cmd, "", output, result)
	}

	// Output diagnostics (not in JSONL mode)
	if witVerbose || len(result.Diagnostics) > 0 {
		outputDiagnostics(cmd, result.Diagnostics)
	}

	if result.Err != nil {
		return fmt.Errorf("build failed: %w", result.Err)
	}

	// Output result as pretty JSON
	if witJSON {
		return outputBuildJSON(cmd, output, result)
	}

	// Write WIT if output path specified
	if witOutputPath != "" {
		if err := os.WriteFile(witOutputPath, []byte(output.Gen.Source), 0644); err != nil {
			return fmt.Errorf("failed to write WIT: %w", err)
		}
		_, _ = fmt.Fprintf(cmd.OutOrStdout(), "Wrote WIT to %s\n", witOutputPath)
	} else {
		// Print generated WIT to stdout
		_, _ = fmt.Fprintln(cmd.OutOrStdout(), output.Gen.Source)
	}

	// Success/validation message
	if output.RoundTripValid {
		successStyle := lipgloss.NewStyle().Foreground(lipgloss.Color("10")).Bold(true)
		_, _ = fmt.Fprintf(cmd.OutOrStdout(), "%s Round-trip validation passed\n", successStyle.Render("VALID"))
	} else {
		warnStyle := lipgloss.NewStyle().Foreground(lipgloss.Color("11")).Bold(true)
		_, _ = fmt.Fprintf(cmd.OutOrStdout(), "%s Round-trip produced different output (lossy conversion)\n", warnStyle.Render("WARN"))
	}

	return nil
}

// runWitBuildBatch processes multiple WIT sources from JSONL input
func runWitBuildBatch(cmd *cobra.Command, _ []string) error {
	inputs, err := readJSONLInputs(witJSONLInput)
	if err != nil {
		return fmt.Errorf("failed to read JSONL input: %w", err)
	}

	// Create pipeline context
	workDir, _ := os.Getwd()
	mount := vfs.NewOSMount("workspace", vfs.MountRW, workDir, vfs.MustVPath("/"))
	overlay := vfs.NewOverlayVFS([]vfs.Mount{mount})
	ctx := pipeline.NewContext(workDir, 0, pipeline.ModeDefault, overlay)

	buildStep := witpipeline.NewBuildStep()
	var hasErrors bool

	for _, input := range inputs {
		// Resolve source for this input
		source, err := resolveJSONLInputSource(input)
		if err != nil {
			// Output error as JSONL
			outputBuildJSONLError(cmd, input.Name, err)
			hasErrors = true
			continue
		}

		buildInput := witpipeline.BuildInput{
			Source: source,
			MakeOptions: witpipeline.MakeOptions{
				WarningsAsErrors: witWarningsAsErrors,
				StrictMode:       witStrictMode,
			},
			GenOptions: witpipeline.GenOptions{
				WarningsAsErrors: witWarningsAsErrors,
			},
		}

		output, result := buildStep.Execute(ctx, buildInput)
		if err := outputBuildJSONL(cmd, input.Name, output, result); err != nil {
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

		_, _ = fmt.Fprintf(cmd.ErrOrStderr(), "  %s %s%s\n", prefix, code, d.Message)
	}
	_, _ = fmt.Fprintln(cmd.ErrOrStderr())
}

// outputMakeJSON outputs make result as JSON
func outputMakeJSON(cmd *cobra.Command, output witpipeline.MakeOutput, result pipeline.StepResult) error {
	jsonResult := map[string]any{
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
	_, _ = fmt.Fprintln(cmd.OutOrStdout(), string(data))
	return nil
}

// outputBuildJSON outputs build result as JSON
func outputBuildJSON(cmd *cobra.Command, output witpipeline.BuildOutput, result pipeline.StepResult) error {
	jsonResult := map[string]any{
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
	_, _ = fmt.Fprintln(cmd.OutOrStdout(), string(data))
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

// ============================================================================
// IR Serialization Helpers
// ============================================================================

// moduleToJSON converts an IR module to a JSON-serializable structure
// since IR types use unexported fields
func moduleToJSON(module witpipeline.MakeOutput) map[string]any {
	result := map[string]any{}

	// Serialize types
	types := module.Module.Types()
	if len(types) > 0 {
		typeList := make([]map[string]any, 0, len(types))
		for _, t := range types {
			typeList = append(typeList, map[string]any{
				"name": t.Name().ToTitleCase(),
			})
		}
		result["types"] = typeList
	}

	// Serialize values (functions)
	values := module.Module.Values()
	if len(values) > 0 {
		valueList := make([]map[string]any, 0, len(values))
		for _, v := range values {
			valueList = append(valueList, map[string]any{
				"name": v.Name().ToTitleCase(),
			})
		}
		result["values"] = valueList
	}

	// Include doc if present
	if doc := module.Module.Doc(); doc != nil && *doc != "" {
		result["doc"] = *doc
	}

	// Include source package info if available
	if ns := module.SourcePackage.Namespace.String(); ns != "" {
		result["sourcePackage"] = map[string]any{
			"namespace": ns,
			"name":      module.SourcePackage.Name.String(),
		}
	}

	return result
}

// ============================================================================
// JSONL Input/Output Functions
// ============================================================================

// readJSONLInputs reads a JSONL file and returns the parsed inputs
func readJSONLInputs(path string) ([]JSONLInput, error) {
	var reader io.Reader

	if path == "-" {
		// Read from stdin
		reader = os.Stdin
	} else {
		file, err := os.Open(path)
		if err != nil {
			return nil, fmt.Errorf("failed to open JSONL file: %w", err)
		}
		defer func() { _ = file.Close() }()
		reader = file
	}

	var inputs []JSONLInput
	scanner := bufio.NewScanner(reader)
	lineNum := 0

	for scanner.Scan() {
		lineNum++
		line := strings.TrimSpace(scanner.Text())

		// Skip empty lines
		if line == "" {
			continue
		}

		var input JSONLInput
		if err := json.Unmarshal([]byte(line), &input); err != nil {
			return nil, fmt.Errorf("line %d: invalid JSON: %w", lineNum, err)
		}

		// Validate input has either source or file
		if input.Source == "" && input.File == "" {
			return nil, fmt.Errorf("line %d: must specify either 'source' or 'file'", lineNum)
		}

		// Default name to line number if not specified
		if input.Name == "" {
			if input.File != "" {
				input.Name = filepath.Base(input.File)
			} else {
				input.Name = fmt.Sprintf("input-%d", lineNum)
			}
		}

		inputs = append(inputs, input)
	}

	if err := scanner.Err(); err != nil {
		return nil, fmt.Errorf("error reading JSONL: %w", err)
	}

	return inputs, nil
}

// resolveJSONLInputSource resolves the source code for a JSONL input
func resolveJSONLInputSource(input JSONLInput) (string, error) {
	if input.Source != "" {
		return input.Source, nil
	}

	if input.File != "" {
		data, err := os.ReadFile(input.File)
		if err != nil {
			return "", fmt.Errorf("failed to read file %s: %w", input.File, err)
		}
		return string(data), nil
	}

	return "", fmt.Errorf("no source or file specified")
}

// outputMakeJSONL outputs a make result as a single JSONL line
func outputMakeJSONL(cmd *cobra.Command, name string, output witpipeline.MakeOutput, result pipeline.StepResult) error {
	out := JSONLMakeOutput{
		Name:        name,
		Success:     result.Err == nil,
		Diagnostics: formatDiagnosticsJSON(result.Diagnostics),
	}

	if result.Err == nil {
		out.TypeCount = len(output.Module.Types())
		out.ValueCount = len(output.Module.Values())
		out.Module = moduleToJSON(output) // Serialize the IR module
	} else {
		out.Error = result.Err.Error()
	}

	return writeJSONL(cmd, out)
}

// outputMakeJSONLError outputs an error for a make input as JSONL
func outputMakeJSONLError(cmd *cobra.Command, name string, err error) {
	out := JSONLMakeOutput{
		Name:    name,
		Success: false,
		Error:   err.Error(),
	}
	_ = writeJSONL(cmd, out)
}

// outputBuildJSONL outputs a build result as a single JSONL line
func outputBuildJSONL(cmd *cobra.Command, name string, output witpipeline.BuildOutput, result pipeline.StepResult) error {
	out := JSONLBuildOutput{
		Name:        name,
		Success:     result.Err == nil,
		Diagnostics: formatDiagnosticsJSON(result.Diagnostics),
	}

	if result.Err == nil {
		out.RoundTripValid = output.RoundTripValid
		out.TypeCount = len(output.Make.Module.Types())
		out.ValueCount = len(output.Make.Module.Values())
		out.Module = moduleToJSON(output.Make) // Serialize the IR module
		out.WITSource = output.Gen.Source
	} else {
		out.Error = result.Err.Error()
	}

	return writeJSONL(cmd, out)
}

// outputBuildJSONLError outputs an error for a build input as JSONL
func outputBuildJSONLError(cmd *cobra.Command, name string, err error) {
	out := JSONLBuildOutput{
		Name:    name,
		Success: false,
		Error:   err.Error(),
	}
	_ = writeJSONL(cmd, out)
}

// writeJSONL writes a value as a single JSON line (no pretty printing)
func writeJSONL(cmd *cobra.Command, v any) error {
	data, err := json.Marshal(v)
	if err != nil {
		return fmt.Errorf("failed to marshal JSONL: %w", err)
	}
	_, _ = fmt.Fprintln(cmd.OutOrStdout(), string(data))
	return nil
}
