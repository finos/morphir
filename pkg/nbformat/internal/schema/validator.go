package schema

import (
	"fmt"
	"strings"
)

// ValidationError represents a schema validation error.
type ValidationError struct {
	Path    string
	Message string
}

func (e ValidationError) Error() string {
	if e.Path == "" {
		return e.Message
	}
	return fmt.Sprintf("%s: %s", e.Path, e.Message)
}

// ValidationResult contains all validation errors found.
type ValidationResult struct {
	Errors []ValidationError
}

// IsValid returns true if there are no validation errors.
func (r ValidationResult) IsValid() bool {
	return len(r.Errors) == 0
}

// Error returns a combined error message or nil if valid.
func (r ValidationResult) Error() error {
	if r.IsValid() {
		return nil
	}
	var msgs []string
	for _, e := range r.Errors {
		msgs = append(msgs, e.Error())
	}
	return fmt.Errorf("validation errors: %s", strings.Join(msgs, "; "))
}

// Add adds a validation error.
func (r *ValidationResult) Add(path, message string) {
	r.Errors = append(r.Errors, ValidationError{Path: path, Message: message})
}

// ValidateOptions configures validation behavior.
type ValidateOptions struct {
	// Strict enables strict validation (all optional fields must be valid if present).
	Strict bool
	// RequireCellIDs requires cell IDs (nbformat 5.1+).
	RequireCellIDs bool
}

// DefaultValidateOptions returns default validation options.
func DefaultValidateOptions() ValidateOptions {
	return ValidateOptions{
		Strict:         false,
		RequireCellIDs: false,
	}
}

// NotebookData represents a decoded notebook for validation.
type NotebookData struct {
	NBFormat      int
	NBFormatMinor int
	Metadata      map[string]any
	Cells         []CellData
}

// CellData represents a decoded cell for validation.
type CellData struct {
	ID             string
	CellType       string
	Source         string
	Metadata       map[string]any
	ExecutionCount *int
	Outputs        []OutputData
	Attachments    map[string]any
}

// OutputData represents a decoded output for validation.
type OutputData struct {
	OutputType     string
	Name           string
	Text           string
	Data           map[string]any
	Metadata       map[string]any
	ExecutionCount *int
	Ename          string
	Evalue         string
	Traceback      []string
}

// ValidateNotebook validates a notebook against the nbformat schema.
func ValidateNotebook(nb NotebookData, opts ValidateOptions) ValidationResult {
	var result ValidationResult

	// Validate format version
	if nb.NBFormat < 4 {
		result.Add("nbformat", fmt.Sprintf("unsupported format version %d (minimum is 4)", nb.NBFormat))
	}
	if nb.NBFormat == 4 && nb.NBFormatMinor < 0 {
		result.Add("nbformat_minor", "nbformat_minor must be non-negative")
	}

	// Validate cells
	for i, cell := range nb.Cells {
		cellPath := fmt.Sprintf("cells[%d]", i)
		validateCell(cell, cellPath, opts, &result)
	}

	return result
}

// validateCell validates a single cell.
func validateCell(cell CellData, path string, opts ValidateOptions, result *ValidationResult) {
	// Validate cell type
	switch cell.CellType {
	case "code", "markdown", "raw":
		// Valid cell types
	case "":
		result.Add(path+".cell_type", "cell_type is required")
	default:
		result.Add(path+".cell_type", fmt.Sprintf("unknown cell type: %s", cell.CellType))
	}

	// Check cell ID if required
	if opts.RequireCellIDs && cell.ID == "" {
		result.Add(path+".id", "cell id is required for nbformat 5.1+")
	}

	// Validate code cell specific fields
	if cell.CellType == "code" {
		for i, output := range cell.Outputs {
			outputPath := fmt.Sprintf("%s.outputs[%d]", path, i)
			validateOutput(output, outputPath, opts, result)
		}
	}

	// Attachments only valid for markdown and raw cells
	if cell.CellType == "code" && len(cell.Attachments) > 0 && opts.Strict {
		result.Add(path+".attachments", "code cells should not have attachments")
	}
}

// validateOutput validates a single output.
func validateOutput(output OutputData, path string, opts ValidateOptions, result *ValidationResult) {
	switch output.OutputType {
	case "stream":
		if output.Name == "" {
			result.Add(path+".name", "stream output requires name field")
		} else if output.Name != "stdout" && output.Name != "stderr" {
			result.Add(path+".name", fmt.Sprintf("stream name must be stdout or stderr, got: %s", output.Name))
		}

	case "display_data":
		if output.Data == nil && opts.Strict {
			result.Add(path+".data", "display_data output requires data field")
		}

	case "execute_result":
		if output.Data == nil && opts.Strict {
			result.Add(path+".data", "execute_result output requires data field")
		}
		if output.ExecutionCount == nil && opts.Strict {
			result.Add(path+".execution_count", "execute_result output requires execution_count field")
		}

	case "error":
		if output.Ename == "" {
			result.Add(path+".ename", "error output requires ename field")
		}
		if output.Evalue == "" && opts.Strict {
			result.Add(path+".evalue", "error output requires evalue field")
		}

	case "":
		result.Add(path+".output_type", "output_type is required")

	default:
		result.Add(path+".output_type", fmt.Sprintf("unknown output type: %s", output.OutputType))
	}
}

// ValidateCellType checks if a cell type is valid.
func ValidateCellType(cellType string) bool {
	switch cellType {
	case "code", "markdown", "raw":
		return true
	default:
		return false
	}
}

// ValidateOutputType checks if an output type is valid.
func ValidateOutputType(outputType string) bool {
	switch outputType {
	case "stream", "display_data", "execute_result", "error":
		return true
	default:
		return false
	}
}

// ValidateStreamName checks if a stream name is valid.
func ValidateStreamName(name string) bool {
	return name == "stdout" || name == "stderr"
}
