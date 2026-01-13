package cmd

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"github.com/charmbracelet/lipgloss"
	"github.com/finos/morphir/cmd/morphir/internal/tui"
	"github.com/finos/morphir/cmd/morphir/internal/tui/components"
	"github.com/finos/morphir/pkg/pipeline"
	"github.com/finos/morphir/pkg/tooling/markdown"
	"github.com/finos/morphir/pkg/tooling/validation"
	"github.com/finos/morphir/pkg/tooling/validation/report"
	"github.com/finos/morphir/pkg/vfs"
	"github.com/spf13/cobra"
)

var (
	validateVersion int
	validateJSON    bool
	validateReport  string
	validateTUI     bool
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

Output Modes:
  - Default: Colored terminal output with summary
  - --tui/-i: Interactive TUI with vim-style navigation
  - --report markdown: Detailed markdown report with glamour rendering
  - --json: Machine-readable JSON output

The TUI mode provides an interactive explorer for validation results with:
  - File list sidebar with status indicators (✓/✗)
  - Markdown report viewer with syntax highlighting
  - Vim-style navigation (j/k, gg/G, /, etc.)
  - Search and filtering capabilities`,
	Args: cobra.MaximumNArgs(1),
	RunE: runValidate,
}

func init() {
	validateCmd.Flags().IntVar(&validateVersion, "version", 0, "Schema version to validate against (1, 2, or 3). Auto-detects if not specified.")
	validateCmd.Flags().BoolVar(&validateJSON, "json", false, "Output result as JSON")
	validateCmd.Flags().StringVar(&validateReport, "report", "", "Generate a detailed report (format: markdown). Output to stdout or specify a file path.")
	validateCmd.Flags().BoolVarP(&validateTUI, "tui", "i", false, "Launch interactive TUI for exploring validation results")
}

// runValidate executes the validate command using the pipeline runner
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

	// Get absolute path for VFS setup
	absIRPath, err := filepath.Abs(irPath)
	if err != nil {
		return fmt.Errorf("failed to get absolute path: %w", err)
	}

	// Determine the workspace root (directory containing the IR file)
	workspaceRoot := filepath.Dir(absIRPath)

	// Create VFS with OS mount for the workspace
	mount := vfs.NewOSMount("workspace", vfs.MountRO, workspaceRoot, vfs.MustVPath("/"))
	overlay := vfs.NewOverlayVFS([]vfs.Mount{mount})

	// Inject the real validation logic from pkg/tooling/validation
	pipeline.SetValidateIRBytes(func(data []byte, sourcePath string, version int) (*pipeline.InternalValidationResult, error) {
		opts := validation.Options{Version: version}
		result, err := validation.ValidateBytes(data, sourcePath, opts)
		if err != nil {
			return nil, err
		}
		return &pipeline.InternalValidationResult{
			Valid:   result.Valid,
			Version: result.Version,
			Path:    result.Path,
			Errors:  result.Errors,
			RawData: result.RawData,
		}, nil
	})

	// Create pipeline context
	ctx := pipeline.NewContext(workspaceRoot, validateVersion, pipeline.ModeDefault, overlay)

	// Create and run the validation pipeline
	validateStep := pipeline.NewValidateStep()
	validationPipeline := pipeline.NewPipeline("validate-ir", "Validates Morphir IR", validateStep)

	// Determine the VFS path for the IR file (relative to workspace root)
	irFileName := filepath.Base(absIRPath)
	vfsIRPath := vfs.MustVPath("/" + irFileName)

	input := pipeline.ValidateInput{
		IRPath:  vfsIRPath,
		Version: validateVersion,
	}

	output, _, err := validationPipeline.Run(ctx, input)
	if err != nil {
		return fmt.Errorf("validation pipeline failed: %w", err)
	}

	// Convert pipeline output to validation.Result for existing output functions
	result := &validation.Result{
		Valid:   output.Valid,
		Version: output.Version,
		Path:    absIRPath, // Use the absolute path for display
		Errors:  output.Errors,
		RawData: output.RawData,
	}

	// Output result using existing output functions
	if validateTUI {
		return outputValidationTUI(cmd, result)
	}
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
		// Output to stdout with glamour rendering (auto-detects TTY)
		renderer := markdown.DefaultRenderer()
		rendered, err := renderer.Render(reportContent, cmd.OutOrStdout())
		if err != nil {
			// Fallback to plain markdown on error
			_, _ = fmt.Fprint(cmd.OutOrStdout(), reportContent)
		} else {
			_, _ = fmt.Fprint(cmd.OutOrStdout(), rendered)
		}
	} else {
		// Treat as file path - always write plain markdown to files
		reportPath := validateReport
		if !strings.HasSuffix(reportPath, ".md") {
			reportPath += ".md"
		}
		if err := os.WriteFile(reportPath, []byte(reportContent), 0644); err != nil {
			return fmt.Errorf("failed to write report: %w", err)
		}
		_, _ = fmt.Fprintf(cmd.ErrOrStderr(), "Report written to %s\n", reportPath)
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

	_, _ = fmt.Fprintf(cmd.OutOrStdout(), `{"valid":%t,"version":%d,"path":%q,"errors":%s}`,
		result.Valid, result.Version, result.Path, errorsStr)
	_, _ = fmt.Fprintln(cmd.OutOrStdout())

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
		_, _ = fmt.Fprintf(cmd.OutOrStdout(), "%s %s %s\n",
			successStyle.Render("VALID"),
			pathStyle.Render(result.Path),
			dimStyle.Render(fmt.Sprintf("(format version %d)", result.Version)))
		return nil
	}

	_, _ = fmt.Fprintf(cmd.OutOrStdout(), "%s %s %s\n",
		errorStyle.Render("INVALID"),
		pathStyle.Render(result.Path),
		dimStyle.Render(fmt.Sprintf("(format version %d)", result.Version)))

	for _, e := range result.Errors {
		_, _ = fmt.Fprintf(cmd.OutOrStdout(), "  %s %s\n",
			errorStyle.Render("-"),
			e)
	}

	return fmt.Errorf("validation failed with %d error(s)", len(result.Errors))
}

func outputValidationTUI(cmd *cobra.Command, result *validation.Result) error {
	// Generate markdown report content
	gen := report.NewGenerator(report.FormatMarkdown)
	reportContent := gen.Generate(result)

	// Create sidebar tree structure
	status := "✓"
	if !result.Valid {
		status = "✗"
	}

	// Extract just the filename for display
	filename := result.Path
	if idx := strings.LastIndex(filename, "/"); idx != -1 {
		filename = filename[idx+1:]
	}
	if idx := strings.LastIndex(filename, "\\"); idx != -1 {
		filename = filename[idx+1:]
	}

	// Create tree structure: Validated Files > filename
	parentItem := &components.SidebarItem{
		ID:    "validated",
		Title: "Validated Files",
		Children: []*components.SidebarItem{
			{
				ID:    result.Path,
				Title: fmt.Sprintf("%s %s", status, filename),
				Data:  result,
			},
		},
	}
	// Expand parent by default to show the file
	parentItem.SetExpanded(true)

	items := []*components.SidebarItem{parentItem}

	// Create TUI app
	var app *tui.App
	app = tui.NewApp(
		tui.WithTitle("Morphir IR Validation Report"),
		tui.WithSidebarTitle("Validated Files"),
		tui.WithSidebar(items),
		tui.WithViewerTitle("Validation Report"),
		tui.WithViewer(reportContent),
		tui.WithOnSelect(func(item *components.SidebarItem) error {
			// When a file is selected, show its validation report
			if validationResult, ok := item.Data.(*validation.Result); ok {
				gen := report.NewGenerator(report.FormatMarkdown)
				content := gen.Generate(validationResult)
				app.SetViewerContent(content)
				app.SetViewerTitle(fmt.Sprintf("Report: %s", validationResult.Path))
			}
			return nil
		}),
	)

	// Run the TUI
	if err := app.Run(); err != nil {
		return fmt.Errorf("TUI error: %w", err)
	}

	// Return error if validation failed (after TUI closes)
	if !result.Valid {
		return fmt.Errorf("validation failed with %d error(s)", len(result.Errors))
	}

	return nil
}
