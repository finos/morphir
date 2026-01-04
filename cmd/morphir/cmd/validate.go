package cmd

import (
	"fmt"
	"os"
	"strings"

	"github.com/charmbracelet/lipgloss"
	"github.com/finos/morphir/pkg/tooling/validation"
	"github.com/finos/morphir/pkg/tooling/validation/report"
	"github.com/spf13/cobra"
)

var (
	validateVersion int
	validateJSON    bool
	validateReport  string
)

var validateCmd = &cobra.Command{
	Use:   "validate [path]",
	Short: "Validate Morphir IR against JSON schema",
	Long: `Validate a Morphir IR file (morphir.ir.json) against the official JSON schema.

If a path is provided, validates the IR at that location. If the path is a directory,
searches for morphir.ir.json within it. If no path is provided, validates the current
directory.

The format version is auto-detected from the formatVersion field in the IR file.
Use --version to force validation against a specific schema version.

Use --report to generate a detailed validation report that explains any errors
and provides suggestions for fixing them.`,
	Args: cobra.MaximumNArgs(1),
	RunE: runValidate,
}

func init() {
	validateCmd.Flags().IntVar(&validateVersion, "version", 0, "Schema version to validate against (1, 2, or 3). Auto-detects if not specified.")
	validateCmd.Flags().BoolVar(&validateJSON, "json", false, "Output result as JSON")
	validateCmd.Flags().StringVar(&validateReport, "report", "", "Generate a detailed report (format: markdown). Output to stdout or specify a file path.")
}

// runValidate executes the validate command
func runValidate(cmd *cobra.Command, args []string) error {
	path := "."
	if len(args) > 0 {
		path = args[0]
	}

	// Find the IR file
	irPath, err := validation.FindIRFile(path)
	if err != nil {
		return fmt.Errorf("failed to find IR file: %w", err)
	}

	// Validate
	opts := validation.Options{
		Version: validateVersion,
	}
	result, err := validation.ValidateFile(irPath, opts)
	if err != nil {
		return fmt.Errorf("validation failed: %w", err)
	}

	// Output result
	if validateReport != "" {
		return outputValidationReport(cmd, result)
	}
	if validateJSON {
		return outputValidationJSON(cmd, result)
	}
	return outputValidationText(cmd, result)
}

func outputValidationReport(cmd *cobra.Command, result *validation.Result) error {
	gen := report.NewGenerator(report.FormatMarkdown)
	reportContent := gen.Generate(result)

	// Determine output destination
	if validateReport == "markdown" || validateReport == "md" {
		// Output to stdout
		fmt.Fprint(cmd.OutOrStdout(), reportContent)
	} else {
		// Treat as file path
		reportPath := validateReport
		if !strings.HasSuffix(reportPath, ".md") {
			reportPath += ".md"
		}
		if err := os.WriteFile(reportPath, []byte(reportContent), 0644); err != nil {
			return fmt.Errorf("failed to write report: %w", err)
		}
		fmt.Fprintf(cmd.ErrOrStderr(), "Report written to %s\n", reportPath)
	}

	if !result.Valid {
		return fmt.Errorf("validation failed with %d error(s)", len(result.Errors))
	}
	return nil
}

func outputValidationJSON(cmd *cobra.Command, result *validation.Result) error {
	// Simple JSON output without external dependency
	errorsStr := "null"
	if len(result.Errors) > 0 {
		var escaped []string
		for _, e := range result.Errors {
			escaped = append(escaped, fmt.Sprintf("%q", e))
		}
		errorsStr = "[" + strings.Join(escaped, ",") + "]"
	}

	fmt.Fprintf(cmd.OutOrStdout(), `{"valid":%t,"version":%d,"path":%q,"errors":%s}`,
		result.Valid, result.Version, result.Path, errorsStr)
	fmt.Fprintln(cmd.OutOrStdout())

	if !result.Valid {
		return fmt.Errorf("validation failed")
	}
	return nil
}

func outputValidationText(cmd *cobra.Command, result *validation.Result) error {
	successStyle := lipgloss.NewStyle().Foreground(lipgloss.Color("10")).Bold(true)
	errorStyle := lipgloss.NewStyle().Foreground(lipgloss.Color("9")).Bold(true)
	pathStyle := lipgloss.NewStyle().Foreground(lipgloss.Color("12"))
	dimStyle := lipgloss.NewStyle().Foreground(lipgloss.Color("8"))

	if result.Valid {
		fmt.Fprintf(cmd.OutOrStdout(), "%s %s %s\n",
			successStyle.Render("VALID"),
			pathStyle.Render(result.Path),
			dimStyle.Render(fmt.Sprintf("(format version %d)", result.Version)))
		return nil
	}

	fmt.Fprintf(cmd.OutOrStdout(), "%s %s %s\n",
		errorStyle.Render("INVALID"),
		pathStyle.Render(result.Path),
		dimStyle.Render(fmt.Sprintf("(format version %d)", result.Version)))

	for _, e := range result.Errors {
		fmt.Fprintf(cmd.OutOrStdout(), "  %s %s\n",
			errorStyle.Render("-"),
			e)
	}

	return fmt.Errorf("validation failed with %d error(s)", len(result.Errors))
}
