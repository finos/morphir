package cmd

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"

	"github.com/finos/morphir/pkg/tooling/decorations"
	"github.com/finos/morphir/pkg/tooling/workspace"
	"github.com/spf13/cobra"
)

var decorationCmd = &cobra.Command{
	Use:   "decoration",
	Short: "Manage Morphir decorations",
	Long:  `Commands for managing Morphir decorations (custom attributes attached to IR nodes).`,
}

var (
	decorationValidateJSON bool
)

var decorationValidateCmd = &cobra.Command{
	Use:   "validate",
	Short: "Validate decoration values against their schemas",
	Long: `Validate all decoration values in the current project against their decoration schemas.

This command:
  - Loads decoration configurations from morphir.json or morphir.toml
  - Loads decoration value files from their storage locations
  - Validates each decoration value against its schema type
  - Reports validation errors with node path context

Use --json for machine-readable output suitable for automation.`,
	RunE: runDecorationValidate,
}

func init() {
	decorationCmd.AddCommand(decorationValidateCmd)
	decorationValidateCmd.Flags().BoolVar(&decorationValidateJSON, "json", false, "Output results as JSON")
	rootCmd.AddCommand(decorationCmd)
}

func runDecorationValidate(cmd *cobra.Command, args []string) error {
	// Load workspace to get project configuration
	lw, err := workspace.LoadFromCwd()
	if err != nil {
		return fmt.Errorf("failed to load workspace: %w", err)
	}

	// Get the root project
	rootProject := lw.RootProject()
	if rootProject == nil {
		return fmt.Errorf("no root project found in workspace")
	}

	projectConfig := rootProject.Config()
	decorationsConfig := projectConfig.Decorations()

	if len(decorationsConfig) == 0 {
		if decorationValidateJSON {
			fmt.Fprintf(cmd.OutOrStdout(), `{"valid":true,"errors":[],"message":"no decorations configured"}`)
			fmt.Fprintln(cmd.OutOrStdout())
			return nil
		}
		fmt.Fprintf(cmd.ErrOrStderr(), "No decorations configured in project\n")
		return nil
	}

	// Validate each decoration
	var allErrors []ValidationError
	workDir, err := os.Getwd()
	if err != nil {
		return fmt.Errorf("failed to get working directory: %w", err)
	}

	for decorationID, decorationConfig := range decorationsConfig {
		// Load decoration IR
		irPath := decorationConfig.IR()
		if !filepath.IsAbs(irPath) {
			irPath = filepath.Join(workDir, irPath)
		}

		decIR, err := decorations.LoadDecorationIR(irPath)
		if err != nil {
			allErrors = append(allErrors, ValidationError{
				DecorationID: decorationID,
				NodePath:     "",
				Message:      fmt.Sprintf("failed to load decoration IR: %v", err),
			})
			continue
		}

		// Load decoration values
		storageLocation := decorationConfig.StorageLocation()
		if !filepath.IsAbs(storageLocation) {
			storageLocation = filepath.Join(workDir, storageLocation)
		}

		values, err := decorations.LoadDecorationValues(storageLocation)
		if err != nil {
			allErrors = append(allErrors, ValidationError{
				DecorationID: decorationID,
				NodePath:     "",
				Message:      fmt.Sprintf("failed to load decoration values: %v", err),
			})
			continue
		}

		// Validate values
		result := decorations.ValidateDecorationValues(decIR, decorationConfig.EntryPoint(), values)
		if !result.Valid {
			for _, validationErr := range result.Errors {
				allErrors = append(allErrors, ValidationError{
					DecorationID: decorationID,
					NodePath:     validationErr.NodePath.String(),
					Message:      validationErr.Message,
				})
			}
		}
	}

	// Output results
	if decorationValidateJSON {
		return outputDecorationValidateJSON(cmd, allErrors)
	}

	return outputDecorationValidateText(cmd, allErrors)
}

// ValidationError represents a decoration validation error.
type ValidationError struct {
	DecorationID string `json:"decoration_id"`
	NodePath     string `json:"node_path"`
	Message      string `json:"message"`
}

func outputDecorationValidateJSON(cmd *cobra.Command, errors []ValidationError) error {
	valid := len(errors) == 0
	output := map[string]interface{}{
		"valid":  valid,
		"errors": errors,
	}

	if valid {
		output["message"] = "all decorations are valid"
	} else {
		output["error_count"] = len(errors)
	}

	encoder := json.NewEncoder(cmd.OutOrStdout())
	encoder.SetIndent("", "  ")
	if err := encoder.Encode(output); err != nil {
		return fmt.Errorf("failed to encode JSON: %w", err)
	}

	if !valid {
		return fmt.Errorf("validation failed with %d error(s)", len(errors))
	}

	return nil
}

func outputDecorationValidateText(cmd *cobra.Command, errors []ValidationError) error {
	if len(errors) == 0 {
		fmt.Fprintf(cmd.OutOrStdout(), "✓ All decorations are valid\n")
		return nil
	}

	fmt.Fprintf(cmd.ErrOrStderr(), "✗ Validation failed with %d error(s):\n\n", len(errors))

	for _, err := range errors {
		if err.NodePath != "" {
			fmt.Fprintf(cmd.ErrOrStderr(), "  [%s] %s: %s\n", err.DecorationID, err.NodePath, err.Message)
		} else {
			fmt.Fprintf(cmd.ErrOrStderr(), "  [%s] %s\n", err.DecorationID, err.Message)
		}
	}

	return fmt.Errorf("validation failed with %d error(s)", len(errors))
}
