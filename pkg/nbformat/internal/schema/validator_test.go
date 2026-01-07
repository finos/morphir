package schema

import (
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestValidationError(t *testing.T) {
	t.Run("error with path", func(t *testing.T) {
		err := ValidationError{Path: "cells[0]", Message: "invalid cell"}
		assert.Equal(t, "cells[0]: invalid cell", err.Error())
	})

	t.Run("error without path", func(t *testing.T) {
		err := ValidationError{Path: "", Message: "invalid notebook"}
		assert.Equal(t, "invalid notebook", err.Error())
	})
}

func TestValidationResult(t *testing.T) {
	t.Run("IsValid when empty", func(t *testing.T) {
		r := ValidationResult{}
		assert.True(t, r.IsValid())
	})

	t.Run("not valid with errors", func(t *testing.T) {
		r := ValidationResult{}
		r.Add("path", "error message")
		assert.False(t, r.IsValid())
	})

	t.Run("Error returns nil when valid", func(t *testing.T) {
		r := ValidationResult{}
		assert.NoError(t, r.Error())
	})

	t.Run("Error returns combined message", func(t *testing.T) {
		r := ValidationResult{}
		r.Add("path1", "error1")
		r.Add("path2", "error2")
		err := r.Error()
		require.Error(t, err)
		assert.Contains(t, err.Error(), "path1: error1")
		assert.Contains(t, err.Error(), "path2: error2")
	})
}

func TestValidateNotebook(t *testing.T) {
	t.Run("valid empty notebook", func(t *testing.T) {
		nb := NotebookData{
			NBFormat:      4,
			NBFormatMinor: 5,
			Cells:         []CellData{},
		}
		result := ValidateNotebook(nb, DefaultValidateOptions())
		assert.True(t, result.IsValid())
	})

	t.Run("valid notebook with cells", func(t *testing.T) {
		nb := NotebookData{
			NBFormat:      4,
			NBFormatMinor: 5,
			Cells: []CellData{
				{CellType: "code", Source: "x = 1"},
				{CellType: "markdown", Source: "# Title"},
				{CellType: "raw", Source: "<html>"},
			},
		}
		result := ValidateNotebook(nb, DefaultValidateOptions())
		assert.True(t, result.IsValid())
	})

	t.Run("invalid nbformat version", func(t *testing.T) {
		nb := NotebookData{
			NBFormat:      3,
			NBFormatMinor: 0,
		}
		result := ValidateNotebook(nb, DefaultValidateOptions())
		assert.False(t, result.IsValid())
		require.Len(t, result.Errors, 1)
		assert.Contains(t, result.Errors[0].Message, "unsupported format version")
	})

	t.Run("invalid cell type", func(t *testing.T) {
		nb := NotebookData{
			NBFormat:      4,
			NBFormatMinor: 5,
			Cells: []CellData{
				{CellType: "invalid"},
			},
		}
		result := ValidateNotebook(nb, DefaultValidateOptions())
		assert.False(t, result.IsValid())
		assert.Contains(t, result.Errors[0].Message, "unknown cell type")
	})

	t.Run("missing cell type", func(t *testing.T) {
		nb := NotebookData{
			NBFormat:      4,
			NBFormatMinor: 5,
			Cells: []CellData{
				{CellType: ""},
			},
		}
		result := ValidateNotebook(nb, DefaultValidateOptions())
		assert.False(t, result.IsValid())
		assert.Contains(t, result.Errors[0].Message, "cell_type is required")
	})
}

func TestValidateCellWithOptions(t *testing.T) {
	t.Run("RequireCellIDs fails for empty ID", func(t *testing.T) {
		nb := NotebookData{
			NBFormat:      4,
			NBFormatMinor: 5,
			Cells: []CellData{
				{CellType: "code", ID: ""},
			},
		}
		opts := ValidateOptions{RequireCellIDs: true}
		result := ValidateNotebook(nb, opts)
		assert.False(t, result.IsValid())
		assert.Contains(t, result.Errors[0].Message, "cell id is required")
	})

	t.Run("RequireCellIDs passes with ID", func(t *testing.T) {
		nb := NotebookData{
			NBFormat:      4,
			NBFormatMinor: 5,
			Cells: []CellData{
				{CellType: "code", ID: "cell-1"},
			},
		}
		opts := ValidateOptions{RequireCellIDs: true}
		result := ValidateNotebook(nb, opts)
		assert.True(t, result.IsValid())
	})
}

func TestValidateOutputs(t *testing.T) {
	t.Run("valid stream output", func(t *testing.T) {
		nb := NotebookData{
			NBFormat:      4,
			NBFormatMinor: 5,
			Cells: []CellData{
				{
					CellType: "code",
					Outputs: []OutputData{
						{OutputType: "stream", Name: "stdout", Text: "hello"},
					},
				},
			},
		}
		result := ValidateNotebook(nb, DefaultValidateOptions())
		assert.True(t, result.IsValid())
	})

	t.Run("stream output missing name", func(t *testing.T) {
		nb := NotebookData{
			NBFormat:      4,
			NBFormatMinor: 5,
			Cells: []CellData{
				{
					CellType: "code",
					Outputs: []OutputData{
						{OutputType: "stream", Name: ""},
					},
				},
			},
		}
		result := ValidateNotebook(nb, DefaultValidateOptions())
		assert.False(t, result.IsValid())
		assert.Contains(t, result.Errors[0].Message, "stream output requires name")
	})

	t.Run("stream output invalid name", func(t *testing.T) {
		nb := NotebookData{
			NBFormat:      4,
			NBFormatMinor: 5,
			Cells: []CellData{
				{
					CellType: "code",
					Outputs: []OutputData{
						{OutputType: "stream", Name: "invalid"},
					},
				},
			},
		}
		result := ValidateNotebook(nb, DefaultValidateOptions())
		assert.False(t, result.IsValid())
		assert.Contains(t, result.Errors[0].Message, "must be stdout or stderr")
	})

	t.Run("error output missing ename", func(t *testing.T) {
		nb := NotebookData{
			NBFormat:      4,
			NBFormatMinor: 5,
			Cells: []CellData{
				{
					CellType: "code",
					Outputs: []OutputData{
						{OutputType: "error", Ename: ""},
					},
				},
			},
		}
		result := ValidateNotebook(nb, DefaultValidateOptions())
		assert.False(t, result.IsValid())
		assert.Contains(t, result.Errors[0].Message, "error output requires ename")
	})

	t.Run("unknown output type", func(t *testing.T) {
		nb := NotebookData{
			NBFormat:      4,
			NBFormatMinor: 5,
			Cells: []CellData{
				{
					CellType: "code",
					Outputs: []OutputData{
						{OutputType: "invalid"},
					},
				},
			},
		}
		result := ValidateNotebook(nb, DefaultValidateOptions())
		assert.False(t, result.IsValid())
		assert.Contains(t, result.Errors[0].Message, "unknown output type")
	})

	t.Run("missing output type", func(t *testing.T) {
		nb := NotebookData{
			NBFormat:      4,
			NBFormatMinor: 5,
			Cells: []CellData{
				{
					CellType: "code",
					Outputs: []OutputData{
						{OutputType: ""},
					},
				},
			},
		}
		result := ValidateNotebook(nb, DefaultValidateOptions())
		assert.False(t, result.IsValid())
		assert.Contains(t, result.Errors[0].Message, "output_type is required")
	})
}

func TestValidateStrictMode(t *testing.T) {
	t.Run("strict mode requires data for display_data", func(t *testing.T) {
		nb := NotebookData{
			NBFormat:      4,
			NBFormatMinor: 5,
			Cells: []CellData{
				{
					CellType: "code",
					Outputs: []OutputData{
						{OutputType: "display_data", Data: nil},
					},
				},
			},
		}
		// Non-strict passes
		result := ValidateNotebook(nb, DefaultValidateOptions())
		assert.True(t, result.IsValid())

		// Strict fails
		result = ValidateNotebook(nb, ValidateOptions{Strict: true})
		assert.False(t, result.IsValid())
	})

	t.Run("strict mode requires execution_count for execute_result", func(t *testing.T) {
		nb := NotebookData{
			NBFormat:      4,
			NBFormatMinor: 5,
			Cells: []CellData{
				{
					CellType: "code",
					Outputs: []OutputData{
						{OutputType: "execute_result", ExecutionCount: nil},
					},
				},
			},
		}
		// Non-strict passes
		result := ValidateNotebook(nb, DefaultValidateOptions())
		assert.True(t, result.IsValid())

		// Strict fails
		result = ValidateNotebook(nb, ValidateOptions{Strict: true})
		assert.False(t, result.IsValid())
	})

	t.Run("strict mode warns about attachments on code cells", func(t *testing.T) {
		nb := NotebookData{
			NBFormat:      4,
			NBFormatMinor: 5,
			Cells: []CellData{
				{
					CellType:    "code",
					Attachments: map[string]any{"image.png": "data"},
				},
			},
		}
		// Non-strict passes
		result := ValidateNotebook(nb, DefaultValidateOptions())
		assert.True(t, result.IsValid())

		// Strict fails
		result = ValidateNotebook(nb, ValidateOptions{Strict: true})
		assert.False(t, result.IsValid())
		assert.Contains(t, result.Errors[0].Message, "code cells should not have attachments")
	})
}

func TestValidateCellType(t *testing.T) {
	assert.True(t, ValidateCellType("code"))
	assert.True(t, ValidateCellType("markdown"))
	assert.True(t, ValidateCellType("raw"))
	assert.False(t, ValidateCellType("invalid"))
	assert.False(t, ValidateCellType(""))
}

func TestValidateOutputType(t *testing.T) {
	assert.True(t, ValidateOutputType("stream"))
	assert.True(t, ValidateOutputType("display_data"))
	assert.True(t, ValidateOutputType("execute_result"))
	assert.True(t, ValidateOutputType("error"))
	assert.False(t, ValidateOutputType("invalid"))
	assert.False(t, ValidateOutputType(""))
}

func TestValidateStreamName(t *testing.T) {
	assert.True(t, ValidateStreamName("stdout"))
	assert.True(t, ValidateStreamName("stderr"))
	assert.False(t, ValidateStreamName("invalid"))
	assert.False(t, ValidateStreamName(""))
}
