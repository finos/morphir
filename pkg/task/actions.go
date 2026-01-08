package task

import (
	"fmt"
	"os"
	"path/filepath"

	"github.com/finos/morphir/pkg/pipeline"
	"github.com/finos/morphir/pkg/tooling/validation"
)

// Built-in action names follow the morphir.* namespace convention.
const (
	ActionValidate = "morphir.validate"
	ActionBuild    = "morphir.build"
	ActionTest     = "morphir.test"
	ActionClean    = "morphir.clean"
)

// DefaultRegistry creates a TaskRegistry pre-populated with built-in actions.
func DefaultRegistry() *TaskRegistry {
	registry := NewTaskRegistry()
	registry.Register(ActionValidate, validateAction)
	registry.Register(ActionBuild, buildAction)
	registry.Register(ActionTest, testAction)
	registry.Register(ActionClean, cleanAction)
	return registry
}

// validateAction validates the morphir.ir.json file against the schema.
// Params:
//   - path: optional path to IR file (defaults to morphir.ir.json in workspace)
//   - version: optional schema version (auto-detected if not specified)
func validateAction(ctx pipeline.Context, params map[string]any) (any, pipeline.StepResult) {
	// Determine the IR file path
	irPath := filepath.Join(ctx.WorkspaceRoot, "morphir.ir.json")
	if p, ok := params["path"].(string); ok && p != "" {
		if filepath.IsAbs(p) {
			irPath = p
		} else {
			irPath = filepath.Join(ctx.WorkspaceRoot, p)
		}
	}

	// Check if file exists
	if _, err := os.Stat(irPath); os.IsNotExist(err) {
		return nil, pipeline.StepResult{
			Diagnostics: []pipeline.Diagnostic{{
				Severity: pipeline.SeverityError,
				Code:     "VALIDATE_NOT_FOUND",
				Message:  fmt.Sprintf("IR file not found: %s", irPath),
				StepName: ActionValidate,
			}},
			Err: fmt.Errorf("IR file not found: %s", irPath),
		}
	}

	// Build validation options
	opts := validation.DefaultOptions()
	if v, ok := params["version"].(int); ok && v > 0 {
		opts.Version = v
	}
	// Handle float64 from JSON parsing
	if v, ok := params["version"].(float64); ok && v > 0 {
		opts.Version = int(v)
	}

	// Run validation
	result, err := validation.ValidateFile(irPath, opts)
	if err != nil {
		return nil, pipeline.StepResult{
			Diagnostics: []pipeline.Diagnostic{{
				Severity: pipeline.SeverityError,
				Code:     "VALIDATE_ERROR",
				Message:  fmt.Sprintf("validation error: %v", err),
				StepName: ActionValidate,
			}},
			Err: err,
		}
	}

	// Convert validation result to diagnostics
	var diagnostics []pipeline.Diagnostic
	if !result.Valid {
		for _, errMsg := range result.Errors {
			diagnostics = append(diagnostics, pipeline.Diagnostic{
				Severity: pipeline.SeverityError,
				Code:     "VALIDATE_SCHEMA",
				Message:  errMsg,
				StepName: ActionValidate,
			})
		}
		return result, pipeline.StepResult{
			Diagnostics: diagnostics,
			Err:         fmt.Errorf("validation failed with %d error(s)", len(result.Errors)),
		}
	}

	// Success
	diagnostics = append(diagnostics, pipeline.Diagnostic{
		Severity: pipeline.SeverityInfo,
		Code:     "VALIDATE_OK",
		Message:  fmt.Sprintf("validated %s (format version %d)", irPath, result.Version),
		StepName: ActionValidate,
	})

	return result, pipeline.StepResult{
		Diagnostics: diagnostics,
	}
}

// buildAction compiles Morphir source files to IR.
// This is a placeholder that will be wired to the actual compiler.
// Params:
//   - source: source directory (defaults to "src")
//   - output: output path (defaults to "morphir.ir.json")
func buildAction(ctx pipeline.Context, params map[string]any) (any, pipeline.StepResult) {
	source := "src"
	if s, ok := params["source"].(string); ok && s != "" {
		source = s
	}

	output := "morphir.ir.json"
	if o, ok := params["output"].(string); ok && o != "" {
		output = o
	}

	sourcePath := filepath.Join(ctx.WorkspaceRoot, source)
	outputPath := filepath.Join(ctx.WorkspaceRoot, output)

	// Check if source directory exists
	info, err := os.Stat(sourcePath)
	if os.IsNotExist(err) {
		return nil, pipeline.StepResult{
			Diagnostics: []pipeline.Diagnostic{{
				Severity: pipeline.SeverityError,
				Code:     "BUILD_NO_SOURCE",
				Message:  fmt.Sprintf("source directory not found: %s", sourcePath),
				StepName: ActionBuild,
			}},
			Err: fmt.Errorf("source directory not found: %s", sourcePath),
		}
	}
	if err != nil {
		return nil, pipeline.StepResult{
			Err: fmt.Errorf("failed to stat source: %w", err),
		}
	}
	if !info.IsDir() {
		return nil, pipeline.StepResult{
			Diagnostics: []pipeline.Diagnostic{{
				Severity: pipeline.SeverityError,
				Code:     "BUILD_NOT_DIR",
				Message:  fmt.Sprintf("source is not a directory: %s", sourcePath),
				StepName: ActionBuild,
			}},
			Err: fmt.Errorf("source is not a directory: %s", sourcePath),
		}
	}

	// Placeholder: actual compilation would happen here
	// For now, return info about what would be done
	result := map[string]any{
		"action":  "build",
		"source":  sourcePath,
		"output":  outputPath,
		"status":  "pending",
		"message": "Build action is a placeholder; compiler integration pending",
	}

	return result, pipeline.StepResult{
		Diagnostics: []pipeline.Diagnostic{{
			Severity: pipeline.SeverityInfo,
			Code:     "BUILD_PENDING",
			Message:  fmt.Sprintf("build: %s -> %s (compiler integration pending)", source, output),
			StepName: ActionBuild,
		}},
	}
}

// testAction runs tests for the Morphir project.
// This is a placeholder that will be wired to test execution.
// Params:
//   - pattern: test pattern to match (defaults to all tests)
//   - verbose: enable verbose output
func testAction(ctx pipeline.Context, params map[string]any) (any, pipeline.StepResult) {
	pattern := "*"
	if p, ok := params["pattern"].(string); ok && p != "" {
		pattern = p
	}

	verbose := false
	if v, ok := params["verbose"].(bool); ok {
		verbose = v
	}

	// Placeholder: actual test execution would happen here
	result := map[string]any{
		"action":  "test",
		"pattern": pattern,
		"verbose": verbose,
		"status":  "pending",
		"message": "Test action is a placeholder; test runner integration pending",
	}

	return result, pipeline.StepResult{
		Diagnostics: []pipeline.Diagnostic{{
			Severity: pipeline.SeverityInfo,
			Code:     "TEST_PENDING",
			Message:  fmt.Sprintf("test: pattern=%s verbose=%v (test runner integration pending)", pattern, verbose),
			StepName: ActionTest,
		}},
	}
}

// cleanAction removes build artifacts from the workspace.
// Params:
//   - patterns: list of glob patterns to clean (defaults to standard artifacts)
//   - dry_run: if true, only report what would be deleted
func cleanAction(ctx pipeline.Context, params map[string]any) (any, pipeline.StepResult) {
	// Default patterns for Morphir artifacts
	patterns := []string{
		"morphir.ir.json",
		".morphir/",
	}
	if p, ok := params["patterns"].([]any); ok && len(p) > 0 {
		patterns = make([]string, 0, len(p))
		for _, item := range p {
			if s, ok := item.(string); ok {
				patterns = append(patterns, s)
			}
		}
	}
	if p, ok := params["patterns"].([]string); ok && len(p) > 0 {
		patterns = p
	}

	dryRun := false
	if d, ok := params["dry_run"].(bool); ok {
		dryRun = d
	}

	var cleaned []string
	var diagnostics []pipeline.Diagnostic

	for _, pattern := range patterns {
		path := filepath.Join(ctx.WorkspaceRoot, pattern)

		// Check if path exists
		info, err := os.Stat(path)
		if os.IsNotExist(err) {
			continue
		}
		if err != nil {
			diagnostics = append(diagnostics, pipeline.Diagnostic{
				Severity: pipeline.SeverityWarn,
				Code:     "CLEAN_STAT_ERROR",
				Message:  fmt.Sprintf("failed to stat %s: %v", pattern, err),
				StepName: ActionClean,
			})
			continue
		}

		if dryRun {
			if info.IsDir() {
				diagnostics = append(diagnostics, pipeline.Diagnostic{
					Severity: pipeline.SeverityInfo,
					Code:     "CLEAN_DRY_RUN",
					Message:  fmt.Sprintf("would remove directory: %s", pattern),
					StepName: ActionClean,
				})
			} else {
				diagnostics = append(diagnostics, pipeline.Diagnostic{
					Severity: pipeline.SeverityInfo,
					Code:     "CLEAN_DRY_RUN",
					Message:  fmt.Sprintf("would remove file: %s", pattern),
					StepName: ActionClean,
				})
			}
			cleaned = append(cleaned, pattern)
			continue
		}

		// Actually remove the file/directory
		if info.IsDir() {
			if err := os.RemoveAll(path); err != nil {
				diagnostics = append(diagnostics, pipeline.Diagnostic{
					Severity: pipeline.SeverityError,
					Code:     "CLEAN_REMOVE_ERROR",
					Message:  fmt.Sprintf("failed to remove directory %s: %v", pattern, err),
					StepName: ActionClean,
				})
				continue
			}
		} else {
			if err := os.Remove(path); err != nil {
				diagnostics = append(diagnostics, pipeline.Diagnostic{
					Severity: pipeline.SeverityError,
					Code:     "CLEAN_REMOVE_ERROR",
					Message:  fmt.Sprintf("failed to remove file %s: %v", pattern, err),
					StepName: ActionClean,
				})
				continue
			}
		}

		cleaned = append(cleaned, pattern)
		diagnostics = append(diagnostics, pipeline.Diagnostic{
			Severity: pipeline.SeverityInfo,
			Code:     "CLEAN_REMOVED",
			Message:  fmt.Sprintf("removed: %s", pattern),
			StepName: ActionClean,
		})
	}

	result := map[string]any{
		"action":  "clean",
		"cleaned": cleaned,
		"dry_run": dryRun,
		"count":   len(cleaned),
	}

	return result, pipeline.StepResult{
		Diagnostics: diagnostics,
	}
}
