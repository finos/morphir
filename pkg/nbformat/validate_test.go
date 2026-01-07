package nbformat

import (
	"testing"

	"github.com/stretchr/testify/assert"
)

func TestValidate(t *testing.T) {
	t.Run("valid notebook passes validation", func(t *testing.T) {
		nb := NewNotebookBuilder().
			AddCodeCell("x = 1").
			AddMarkdownCell("# Title").
			Build()

		result := Validate(nb)
		assert.True(t, result.IsValid())
		assert.NoError(t, result.Error())
	})

	t.Run("valid notebook with outputs passes", func(t *testing.T) {
		cell := NewCodeCellBuilder().
			WithSource("print('hello')").
			AddStdoutOutput("hello\n").
			Build()

		nb := NewNotebook().AddCell(cell)
		result := Validate(nb)
		assert.True(t, result.IsValid())
	})

	t.Run("valid notebook with error output passes", func(t *testing.T) {
		cell := NewCodeCellBuilder().
			WithSource("1/0").
			AddErrorOutput("ZeroDivisionError", "division by zero", []string{"trace"}).
			Build()

		nb := NewNotebook().AddCell(cell)
		result := Validate(nb)
		assert.True(t, result.IsValid())
	})

	t.Run("valid notebook with execute_result passes", func(t *testing.T) {
		data := NewMimeBundle().WithData("text/plain", "42")
		cell := NewCodeCellBuilder().
			WithSource("6 * 7").
			AddExecuteResultOutput(1, data).
			Build()

		nb := NewNotebook().AddCell(cell)
		result := Validate(nb)
		assert.True(t, result.IsValid())
	})

	t.Run("valid notebook with display_data passes", func(t *testing.T) {
		data := NewMimeBundle().WithData("image/png", "base64data")
		cell := NewCodeCellBuilder().
			WithSource("display(fig)").
			AddDisplayDataOutput(data).
			Build()

		nb := NewNotebook().AddCell(cell)
		result := Validate(nb)
		assert.True(t, result.IsValid())
	})
}

func TestValidateWithOptions(t *testing.T) {
	t.Run("strict mode requires cell IDs when enabled", func(t *testing.T) {
		nb := NewNotebookBuilder().
			AddCodeCell("x = 1").
			Build()

		// Without RequireCellIDs
		result := ValidateWithOptions(nb, ValidateOptions{RequireCellIDs: false})
		assert.True(t, result.IsValid())

		// With RequireCellIDs
		result = ValidateWithOptions(nb, ValidateOptions{RequireCellIDs: true})
		assert.False(t, result.IsValid())
		assert.Len(t, result.Errors(), 1)
		assert.Contains(t, result.Errors()[0].Message, "cell id is required")
	})

	t.Run("cell with ID passes RequireCellIDs", func(t *testing.T) {
		nb := NewNotebookBuilder().
			AddCodeCellWithID("cell-1", "x = 1").
			Build()

		result := ValidateWithOptions(nb, ValidateOptions{RequireCellIDs: true})
		assert.True(t, result.IsValid())
	})
}

func TestValidateStreamOutput(t *testing.T) {
	t.Run("valid stdout", func(t *testing.T) {
		cell := NewCodeCellBuilder().
			AddStdoutOutput("hello").
			Build()

		nb := NewNotebook().AddCell(cell)
		result := Validate(nb)
		assert.True(t, result.IsValid())
	})

	t.Run("valid stderr", func(t *testing.T) {
		cell := NewCodeCellBuilder().
			AddStderrOutput("error").
			Build()

		nb := NewNotebook().AddCell(cell)
		result := Validate(nb)
		assert.True(t, result.IsValid())
	})
}

func TestValidateErrorOutput(t *testing.T) {
	t.Run("error with all fields", func(t *testing.T) {
		cell := NewCodeCellBuilder().
			AddErrorOutput("Error", "message", []string{"line1", "line2"}).
			Build()

		nb := NewNotebook().AddCell(cell)
		result := Validate(nb)
		assert.True(t, result.IsValid())
	})

	t.Run("error without traceback is valid", func(t *testing.T) {
		cell := NewCodeCellBuilder().
			AddErrorOutput("Error", "message", nil).
			Build()

		nb := NewNotebook().AddCell(cell)
		result := Validate(nb)
		assert.True(t, result.IsValid())
	})
}

func TestIsValidCellType(t *testing.T) {
	tests := []struct {
		cellType CellType
		valid    bool
	}{
		{CellTypeCode, true},
		{CellTypeMarkdown, true},
		{CellTypeRaw, true},
		{CellType("invalid"), false},
		{CellType(""), false},
	}

	for _, tt := range tests {
		t.Run(string(tt.cellType), func(t *testing.T) {
			assert.Equal(t, tt.valid, IsValidCellType(tt.cellType))
		})
	}
}

func TestIsValidOutputType(t *testing.T) {
	tests := []struct {
		outputType OutputType
		valid      bool
	}{
		{OutputTypeStream, true},
		{OutputTypeDisplayData, true},
		{OutputTypeExecuteResult, true},
		{OutputTypeError, true},
		{OutputType("invalid"), false},
		{OutputType(""), false},
	}

	for _, tt := range tests {
		t.Run(string(tt.outputType), func(t *testing.T) {
			assert.Equal(t, tt.valid, IsValidOutputType(tt.outputType))
		})
	}
}

func TestIsValidStreamName(t *testing.T) {
	tests := []struct {
		name  StreamName
		valid bool
	}{
		{StreamStdout, true},
		{StreamStderr, true},
		{StreamName("invalid"), false},
		{StreamName(""), false},
	}

	for _, tt := range tests {
		t.Run(string(tt.name), func(t *testing.T) {
			assert.Equal(t, tt.valid, IsValidStreamName(tt.name))
		})
	}
}

func TestValidationResult(t *testing.T) {
	t.Run("IsValid returns true for valid notebook", func(t *testing.T) {
		nb := NewNotebook()
		result := Validate(nb)
		assert.True(t, result.IsValid())
		assert.Empty(t, result.Errors())
	})

	t.Run("Error returns nil for valid notebook", func(t *testing.T) {
		nb := NewNotebook()
		result := Validate(nb)
		assert.NoError(t, result.Error())
	})
}
