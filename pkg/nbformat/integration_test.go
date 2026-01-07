package nbformat

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestIntegration_ReadSampleNotebook(t *testing.T) {
	path := filepath.Join("testdata", "sample.ipynb")

	t.Run("reads sample notebook file", func(t *testing.T) {
		nb, err := ReadFile(path)
		require.NoError(t, err)

		assert.Equal(t, 4, nb.NBFormat())
		assert.Equal(t, 5, nb.NBFormatMinor())
		assert.Equal(t, 5, nb.CellCount())
	})

	t.Run("reads metadata correctly", func(t *testing.T) {
		nb, err := ReadFile(path)
		require.NoError(t, err)

		meta := nb.Metadata()
		require.NotNil(t, meta.KernelSpec())
		assert.Equal(t, "python3", meta.KernelSpec().Name())
		assert.Equal(t, "Python 3 (ipykernel)", meta.KernelSpec().DisplayName())
		assert.Equal(t, "python", meta.KernelSpec().Language())

		require.NotNil(t, meta.LanguageInfo())
		assert.Equal(t, "python", meta.LanguageInfo().Name())
		assert.Equal(t, "3.10.0", meta.LanguageInfo().Version())
		assert.Equal(t, ".py", meta.LanguageInfo().FileExtension())
		assert.Equal(t, "text/x-python", meta.LanguageInfo().MimeType())
	})

	t.Run("reads markdown cell", func(t *testing.T) {
		nb, err := ReadFile(path)
		require.NoError(t, err)

		cell := nb.Cell(0)
		assert.Equal(t, CellTypeMarkdown, cell.CellType())
		assert.Equal(t, "markdown-cell-1", cell.ID())
		assert.Contains(t, cell.Source(), "# Sample Notebook")
	})

	t.Run("reads code cell with stream output", func(t *testing.T) {
		nb, err := ReadFile(path)
		require.NoError(t, err)

		cell := nb.Cell(1).(CodeCell)
		assert.Equal(t, CellTypeCode, cell.CellType())
		assert.Equal(t, "code-cell-1", cell.ID())
		assert.Equal(t, ScrolledTrue, cell.Metadata().Scrolled())

		require.NotNil(t, cell.ExecutionCount())
		assert.Equal(t, 1, *cell.ExecutionCount())

		outputs := cell.Outputs()
		require.Len(t, outputs, 1)

		stream := outputs[0].(StreamOutput)
		assert.Equal(t, OutputTypeStream, stream.OutputType())
		assert.Equal(t, StreamStdout, stream.Name())
		assert.Contains(t, stream.Text(), "Hello, World!")
	})

	t.Run("reads code cell with execute_result", func(t *testing.T) {
		nb, err := ReadFile(path)
		require.NoError(t, err)

		cell := nb.Cell(2).(CodeCell)
		outputs := cell.Outputs()
		require.Len(t, outputs, 1)

		result := outputs[0].(ExecuteResultOutput)
		assert.Equal(t, OutputTypeExecuteResult, result.OutputType())
		assert.Equal(t, 2, result.ExecutionCount())

		val, ok := result.Data().Get("text/plain")
		assert.True(t, ok)
		assert.Equal(t, "42", val)
	})

	t.Run("reads code cell with error output", func(t *testing.T) {
		nb, err := ReadFile(path)
		require.NoError(t, err)

		cell := nb.Cell(3).(CodeCell)
		outputs := cell.Outputs()
		require.Len(t, outputs, 1)

		errOut := outputs[0].(ErrorOutput)
		assert.Equal(t, OutputTypeError, errOut.OutputType())
		assert.Equal(t, "ZeroDivisionError", errOut.Ename())
		assert.Equal(t, "division by zero", errOut.Evalue())
		assert.NotEmpty(t, errOut.Traceback())
	})

	t.Run("reads raw cell", func(t *testing.T) {
		nb, err := ReadFile(path)
		require.NoError(t, err)

		cell := nb.Cell(4)
		assert.Equal(t, CellTypeRaw, cell.CellType())
		assert.Equal(t, "raw-cell-1", cell.ID())
		assert.Contains(t, cell.Source(), "<html>")
	})

	t.Run("validates successfully", func(t *testing.T) {
		nb, err := ReadFile(path)
		require.NoError(t, err)

		result := Validate(nb)
		assert.True(t, result.IsValid())
	})

	t.Run("validates with RequireCellIDs", func(t *testing.T) {
		nb, err := ReadFile(path)
		require.NoError(t, err)

		result := ValidateWithOptions(nb, ValidateOptions{RequireCellIDs: true})
		assert.True(t, result.IsValid())
	})
}

func TestIntegration_RoundTrip(t *testing.T) {
	path := filepath.Join("testdata", "sample.ipynb")

	t.Run("read-write-read produces equivalent notebook", func(t *testing.T) {
		// Read original
		nb1, err := ReadFile(path)
		require.NoError(t, err)

		// Write to temp file
		tempFile := filepath.Join(t.TempDir(), "roundtrip.ipynb")
		err = WriteFile(nb1, tempFile)
		require.NoError(t, err)

		// Read back
		nb2, err := ReadFile(tempFile)
		require.NoError(t, err)

		// Compare
		assert.Equal(t, nb1.NBFormat(), nb2.NBFormat())
		assert.Equal(t, nb1.NBFormatMinor(), nb2.NBFormatMinor())
		assert.Equal(t, nb1.CellCount(), nb2.CellCount())

		for i := 0; i < nb1.CellCount(); i++ {
			c1 := nb1.Cell(i)
			c2 := nb2.Cell(i)
			assert.Equal(t, c1.CellType(), c2.CellType(), "cell %d type mismatch", i)
			assert.Equal(t, c1.ID(), c2.ID(), "cell %d ID mismatch", i)
			assert.Equal(t, c1.Source(), c2.Source(), "cell %d source mismatch", i)
		}
	})

	t.Run("preserves code cell outputs", func(t *testing.T) {
		nb1, err := ReadFile(path)
		require.NoError(t, err)

		tempFile := filepath.Join(t.TempDir(), "outputs.ipynb")
		err = WriteFile(nb1, tempFile)
		require.NoError(t, err)

		nb2, err := ReadFile(tempFile)
		require.NoError(t, err)

		// Check stream output
		code1 := nb1.Cell(1).(CodeCell)
		code2 := nb2.Cell(1).(CodeCell)
		assert.Equal(t, len(code1.Outputs()), len(code2.Outputs()))

		stream1 := code1.Outputs()[0].(StreamOutput)
		stream2 := code2.Outputs()[0].(StreamOutput)
		assert.Equal(t, stream1.Name(), stream2.Name())
		assert.Equal(t, stream1.Text(), stream2.Text())

		// Check error output
		errCode1 := nb1.Cell(3).(CodeCell)
		errCode2 := nb2.Cell(3).(CodeCell)
		err1 := errCode1.Outputs()[0].(ErrorOutput)
		err2 := errCode2.Outputs()[0].(ErrorOutput)
		assert.Equal(t, err1.Ename(), err2.Ename())
		assert.Equal(t, err1.Evalue(), err2.Evalue())
	})

	t.Run("preserves metadata", func(t *testing.T) {
		nb1, err := ReadFile(path)
		require.NoError(t, err)

		tempFile := filepath.Join(t.TempDir(), "metadata.ipynb")
		err = WriteFile(nb1, tempFile)
		require.NoError(t, err)

		nb2, err := ReadFile(tempFile)
		require.NoError(t, err)

		meta1 := nb1.Metadata()
		meta2 := nb2.Metadata()

		assert.Equal(t, meta1.KernelSpec().Name(), meta2.KernelSpec().Name())
		assert.Equal(t, meta1.KernelSpec().DisplayName(), meta2.KernelSpec().DisplayName())
		assert.Equal(t, meta1.LanguageInfo().Name(), meta2.LanguageInfo().Name())
		assert.Equal(t, meta1.LanguageInfo().Version(), meta2.LanguageInfo().Version())
	})
}

func TestIntegration_WriteAndRead(t *testing.T) {
	t.Run("creates and reads back new notebook", func(t *testing.T) {
		// Create a notebook programmatically
		nb := NewNotebookBuilder().
			WithKernelSpec("python3", "Python 3").
			WithLanguageInfo("python").
			WithTitle("Test Notebook").
			AddMarkdownCell("# Test Notebook\n\nCreated programmatically.").
			AddCodeCell("x = 1\ny = 2\nprint(x + y)").
			AddRawCell("<html><body>Test</body></html>").
			Build()

		// Write to temp file
		tempFile := filepath.Join(t.TempDir(), "created.ipynb")
		err := WriteFile(nb, tempFile)
		require.NoError(t, err)

		// Verify file exists
		_, err = os.Stat(tempFile)
		require.NoError(t, err)

		// Read back
		nb2, err := ReadFile(tempFile)
		require.NoError(t, err)

		assert.Equal(t, 4, nb2.NBFormat())
		assert.Equal(t, 3, nb2.CellCount())
		assert.Equal(t, CellTypeMarkdown, nb2.Cell(0).CellType())
		assert.Equal(t, CellTypeCode, nb2.Cell(1).CellType())
		assert.Equal(t, CellTypeRaw, nb2.Cell(2).CellType())
	})
}

func TestIntegration_HasErrors(t *testing.T) {
	path := filepath.Join("testdata", "sample.ipynb")

	t.Run("detects error in notebook", func(t *testing.T) {
		nb, err := ReadFile(path)
		require.NoError(t, err)

		assert.True(t, HasErrors(nb))
	})
}

func TestIntegration_ClearOutputs(t *testing.T) {
	path := filepath.Join("testdata", "sample.ipynb")

	t.Run("clears all outputs", func(t *testing.T) {
		nb, err := ReadFile(path)
		require.NoError(t, err)

		// Verify original has outputs
		codeCell := nb.Cell(1).(CodeCell)
		require.NotEmpty(t, codeCell.Outputs())

		// Clear outputs
		cleared := ClearOutputs(nb)

		// Verify cleared
		clearedCode := cleared.Cell(1).(CodeCell)
		assert.Empty(t, clearedCode.Outputs())

		// Original unchanged
		assert.NotEmpty(t, codeCell.Outputs())
	})
}

func TestIntegration_TraverseCells(t *testing.T) {
	path := filepath.Join("testdata", "sample.ipynb")

	t.Run("collects code cells", func(t *testing.T) {
		nb, err := ReadFile(path)
		require.NoError(t, err)

		codeCells := CollectCodeCells(nb)
		assert.Len(t, codeCells, 3)
	})

	t.Run("collects markdown cells", func(t *testing.T) {
		nb, err := ReadFile(path)
		require.NoError(t, err)

		mdCells := CollectMarkdownCells(nb)
		assert.Len(t, mdCells, 1)
	})

	t.Run("filters cells by type", func(t *testing.T) {
		nb, err := ReadFile(path)
		require.NoError(t, err)

		codeOnly := FilterCells(nb, func(c Cell) bool {
			return c.CellType() == CellTypeCode
		})

		assert.Equal(t, 3, codeOnly.CellCount())
	})
}
