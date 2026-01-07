package nbformat

import (
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestNotebookBuilder(t *testing.T) {
	t.Run("creates notebook with default version", func(t *testing.T) {
		notebook := NewNotebookBuilder().Build()

		assert.Equal(t, NBFormat, notebook.NBFormat())
		assert.Equal(t, NBFormatMinor, notebook.NBFormatMinor())
		assert.Nil(t, notebook.Cells())
	})

	t.Run("sets format version", func(t *testing.T) {
		notebook := NewNotebookBuilder().
			WithNBFormat(4, 4).
			Build()

		assert.Equal(t, 4, notebook.NBFormat())
		assert.Equal(t, 4, notebook.NBFormatMinor())
	})

	t.Run("sets metadata", func(t *testing.T) {
		meta := NewNotebookMetadata().WithTitle("Test Notebook")
		notebook := NewNotebookBuilder().
			WithMetadata(meta).
			Build()

		assert.Equal(t, "Test Notebook", notebook.Metadata().Title())
	})

	t.Run("sets kernel spec", func(t *testing.T) {
		notebook := NewNotebookBuilder().
			WithKernelSpec("python3", "Python 3").
			Build()

		require.NotNil(t, notebook.Metadata().KernelSpec())
		assert.Equal(t, "python3", notebook.Metadata().KernelSpec().Name())
		assert.Equal(t, "Python 3", notebook.Metadata().KernelSpec().DisplayName())
	})

	t.Run("sets language info", func(t *testing.T) {
		notebook := NewNotebookBuilder().
			WithLanguageInfo("python").
			Build()

		require.NotNil(t, notebook.Metadata().LanguageInfo())
		assert.Equal(t, "python", notebook.Metadata().LanguageInfo().Name())
	})

	t.Run("sets title", func(t *testing.T) {
		notebook := NewNotebookBuilder().
			WithTitle("My Notebook").
			Build()

		assert.Equal(t, "My Notebook", notebook.Metadata().Title())
	})

	t.Run("adds single cell", func(t *testing.T) {
		notebook := NewNotebookBuilder().
			AddCell(NewCodeCell("x = 1")).
			Build()

		require.Len(t, notebook.Cells(), 1)
		assert.Equal(t, "x = 1", notebook.Cells()[0].Source())
	})

	t.Run("adds multiple cells", func(t *testing.T) {
		notebook := NewNotebookBuilder().
			AddCells(
				NewCodeCell("x = 1"),
				NewMarkdownCell("# Title"),
				NewRawCell("<html>"),
			).
			Build()

		require.Len(t, notebook.Cells(), 3)
	})

	t.Run("adds code cell with source", func(t *testing.T) {
		notebook := NewNotebookBuilder().
			AddCodeCell("print('hello')").
			Build()

		cells := notebook.Cells()
		require.Len(t, cells, 1)
		assert.Equal(t, CellTypeCode, cells[0].CellType())
		assert.Equal(t, "print('hello')", cells[0].Source())
	})

	t.Run("adds code cell with ID", func(t *testing.T) {
		notebook := NewNotebookBuilder().
			AddCodeCellWithID("cell-1", "x = 1").
			Build()

		cells := notebook.Cells()
		assert.Equal(t, "cell-1", cells[0].ID())
	})

	t.Run("adds markdown cell with source", func(t *testing.T) {
		notebook := NewNotebookBuilder().
			AddMarkdownCell("# Title").
			Build()

		cells := notebook.Cells()
		require.Len(t, cells, 1)
		assert.Equal(t, CellTypeMarkdown, cells[0].CellType())
	})

	t.Run("adds markdown cell with ID", func(t *testing.T) {
		notebook := NewNotebookBuilder().
			AddMarkdownCellWithID("md-1", "# Title").
			Build()

		cells := notebook.Cells()
		assert.Equal(t, "md-1", cells[0].ID())
	})

	t.Run("adds raw cell with source", func(t *testing.T) {
		notebook := NewNotebookBuilder().
			AddRawCell("<html>").
			Build()

		cells := notebook.Cells()
		require.Len(t, cells, 1)
		assert.Equal(t, CellTypeRaw, cells[0].CellType())
	})

	t.Run("adds raw cell with ID", func(t *testing.T) {
		notebook := NewNotebookBuilder().
			AddRawCellWithID("raw-1", "<html>").
			Build()

		cells := notebook.Cells()
		assert.Equal(t, "raw-1", cells[0].ID())
	})

	t.Run("build creates defensive copy", func(t *testing.T) {
		builder := NewNotebookBuilder().
			AddCodeCell("x = 1")

		notebook := builder.Build()

		// Modify builder after build
		builder.AddCodeCell("y = 2")

		// Original notebook should be unaffected
		assert.Len(t, notebook.Cells(), 1)
	})

	t.Run("reset clears builder state", func(t *testing.T) {
		builder := NewNotebookBuilder().
			WithNBFormat(4, 4).
			WithTitle("Test").
			AddCodeCell("x = 1")

		builder.Reset()
		notebook := builder.Build()

		assert.Equal(t, NBFormat, notebook.NBFormat())
		assert.Equal(t, NBFormatMinor, notebook.NBFormatMinor())
		assert.Empty(t, notebook.Metadata().Title())
		assert.Nil(t, notebook.Cells())
	})

	t.Run("fluent builder chain", func(t *testing.T) {
		notebook := NewNotebookBuilder().
			WithKernelSpec("python3", "Python 3").
			WithLanguageInfo("python").
			WithTitle("Data Analysis").
			AddMarkdownCell("# Data Analysis").
			AddCodeCell("import pandas as pd").
			AddCodeCell("df = pd.read_csv('data.csv')").
			AddMarkdownCell("## Summary").
			AddCodeCell("df.describe()").
			Build()

		assert.Equal(t, 5, notebook.CellCount())
		require.NotNil(t, notebook.Metadata().KernelSpec())
		assert.Equal(t, "Data Analysis", notebook.Metadata().Title())
	})
}

func TestCodeCellBuilder(t *testing.T) {
	t.Run("creates code cell with defaults", func(t *testing.T) {
		cell := NewCodeCellBuilder().Build()

		assert.Empty(t, cell.ID())
		assert.Empty(t, cell.Source())
		assert.Nil(t, cell.ExecutionCount())
		assert.Nil(t, cell.Outputs())
	})

	t.Run("sets ID", func(t *testing.T) {
		cell := NewCodeCellBuilder().
			WithID("cell-1").
			Build()

		assert.Equal(t, "cell-1", cell.ID())
	})

	t.Run("sets source", func(t *testing.T) {
		cell := NewCodeCellBuilder().
			WithSource("x = 1").
			Build()

		assert.Equal(t, "x = 1", cell.Source())
	})

	t.Run("sets metadata", func(t *testing.T) {
		meta := NewCellMetadata().WithName("my-cell")
		cell := NewCodeCellBuilder().
			WithMetadata(meta).
			Build()

		assert.Equal(t, "my-cell", cell.Metadata().Name())
	})

	t.Run("sets execution count", func(t *testing.T) {
		cell := NewCodeCellBuilder().
			WithExecutionCount(5).
			Build()

		require.NotNil(t, cell.ExecutionCount())
		assert.Equal(t, 5, *cell.ExecutionCount())
	})

	t.Run("adds output", func(t *testing.T) {
		cell := NewCodeCellBuilder().
			AddOutput(NewStdoutOutput("hello")).
			Build()

		require.Len(t, cell.Outputs(), 1)
	})

	t.Run("adds stream output", func(t *testing.T) {
		cell := NewCodeCellBuilder().
			AddStreamOutput(StreamStdout, "hello").
			Build()

		outputs := cell.Outputs()
		require.Len(t, outputs, 1)
		stream := outputs[0].(StreamOutput)
		assert.Equal(t, StreamStdout, stream.Name())
		assert.Equal(t, "hello", stream.Text())
	})

	t.Run("adds stdout output", func(t *testing.T) {
		cell := NewCodeCellBuilder().
			AddStdoutOutput("hello").
			Build()

		outputs := cell.Outputs()
		stream := outputs[0].(StreamOutput)
		assert.Equal(t, StreamStdout, stream.Name())
	})

	t.Run("adds stderr output", func(t *testing.T) {
		cell := NewCodeCellBuilder().
			AddStderrOutput("error").
			Build()

		outputs := cell.Outputs()
		stream := outputs[0].(StreamOutput)
		assert.Equal(t, StreamStderr, stream.Name())
	})

	t.Run("adds error output", func(t *testing.T) {
		cell := NewCodeCellBuilder().
			AddErrorOutput("ZeroDivisionError", "division by zero", []string{"line 1"}).
			Build()

		outputs := cell.Outputs()
		errOut := outputs[0].(ErrorOutput)
		assert.Equal(t, "ZeroDivisionError", errOut.Ename())
		assert.Equal(t, "division by zero", errOut.Evalue())
	})

	t.Run("adds display data output", func(t *testing.T) {
		data := NewMimeBundle().WithData("text/plain", "hello")
		cell := NewCodeCellBuilder().
			AddDisplayDataOutput(data).
			Build()

		outputs := cell.Outputs()
		display := outputs[0].(DisplayDataOutput)
		val, _ := display.Data().Get("text/plain")
		assert.Equal(t, "hello", val)
	})

	t.Run("adds execute result output", func(t *testing.T) {
		data := NewMimeBundle().WithData("text/plain", "result")
		cell := NewCodeCellBuilder().
			AddExecuteResultOutput(5, data).
			Build()

		outputs := cell.Outputs()
		result := outputs[0].(ExecuteResultOutput)
		assert.Equal(t, 5, result.ExecutionCount())
	})

	t.Run("reset clears state", func(t *testing.T) {
		builder := NewCodeCellBuilder().
			WithID("cell-1").
			WithSource("x = 1").
			AddStdoutOutput("hello")

		builder.Reset()
		cell := builder.Build()

		assert.Empty(t, cell.ID())
		assert.Empty(t, cell.Source())
		assert.Nil(t, cell.Outputs())
	})
}

func TestMarkdownCellBuilder(t *testing.T) {
	t.Run("creates markdown cell with defaults", func(t *testing.T) {
		cell := NewMarkdownCellBuilder().Build()

		assert.Empty(t, cell.ID())
		assert.Empty(t, cell.Source())
		assert.Nil(t, cell.Attachments())
	})

	t.Run("sets ID", func(t *testing.T) {
		cell := NewMarkdownCellBuilder().
			WithID("md-1").
			Build()

		assert.Equal(t, "md-1", cell.ID())
	})

	t.Run("sets source", func(t *testing.T) {
		cell := NewMarkdownCellBuilder().
			WithSource("# Title").
			Build()

		assert.Equal(t, "# Title", cell.Source())
	})

	t.Run("sets metadata", func(t *testing.T) {
		meta := NewCellMetadata().WithName("my-markdown")
		cell := NewMarkdownCellBuilder().
			WithMetadata(meta).
			Build()

		assert.Equal(t, "my-markdown", cell.Metadata().Name())
	})

	t.Run("adds attachment", func(t *testing.T) {
		data := NewMimeBundle().WithData("image/png", "base64data")
		cell := NewMarkdownCellBuilder().
			AddAttachment("image.png", data).
			Build()

		attachments := cell.Attachments()
		require.Contains(t, attachments, "image.png")
		val, _ := attachments["image.png"].Get("image/png")
		assert.Equal(t, "base64data", val)
	})

	t.Run("reset clears state", func(t *testing.T) {
		builder := NewMarkdownCellBuilder().
			WithID("md-1").
			WithSource("# Title")

		builder.Reset()
		cell := builder.Build()

		assert.Empty(t, cell.ID())
		assert.Empty(t, cell.Source())
	})
}

func TestRawCellBuilder(t *testing.T) {
	t.Run("creates raw cell with defaults", func(t *testing.T) {
		cell := NewRawCellBuilder().Build()

		assert.Empty(t, cell.ID())
		assert.Empty(t, cell.Source())
		assert.Nil(t, cell.Attachments())
	})

	t.Run("sets all properties", func(t *testing.T) {
		cell := NewRawCellBuilder().
			WithID("raw-1").
			WithSource("<html>").
			Build()

		assert.Equal(t, "raw-1", cell.ID())
		assert.Equal(t, "<html>", cell.Source())
	})

	t.Run("adds attachment", func(t *testing.T) {
		data := NewMimeBundle().WithData("text/html", "<b>bold</b>")
		cell := NewRawCellBuilder().
			AddAttachment("snippet.html", data).
			Build()

		attachments := cell.Attachments()
		require.Contains(t, attachments, "snippet.html")
	})

	t.Run("reset clears state", func(t *testing.T) {
		builder := NewRawCellBuilder().
			WithID("raw-1").
			WithSource("<html>")

		builder.Reset()
		cell := builder.Build()

		assert.Empty(t, cell.ID())
		assert.Empty(t, cell.Source())
	})
}

func TestMimeBundleBuilder(t *testing.T) {
	t.Run("creates empty bundle", func(t *testing.T) {
		bundle := NewMimeBundleBuilder().Build()
		assert.Nil(t, bundle.Data())
	})

	t.Run("adds data", func(t *testing.T) {
		bundle := NewMimeBundleBuilder().
			WithData("custom/type", "custom data").
			Build()

		val, ok := bundle.Get("custom/type")
		assert.True(t, ok)
		assert.Equal(t, "custom data", val)
	})

	t.Run("adds text/plain", func(t *testing.T) {
		bundle := NewMimeBundleBuilder().
			WithTextPlain("hello").
			Build()

		val, ok := bundle.Get("text/plain")
		assert.True(t, ok)
		assert.Equal(t, "hello", val)
	})

	t.Run("adds text/html", func(t *testing.T) {
		bundle := NewMimeBundleBuilder().
			WithTextHTML("<b>hello</b>").
			Build()

		val, ok := bundle.Get("text/html")
		assert.True(t, ok)
		assert.Equal(t, "<b>hello</b>", val)
	})

	t.Run("adds image/png", func(t *testing.T) {
		bundle := NewMimeBundleBuilder().
			WithImagePNG("base64data").
			Build()

		val, ok := bundle.Get("image/png")
		assert.True(t, ok)
		assert.Equal(t, "base64data", val)
	})

	t.Run("adds image/jpeg", func(t *testing.T) {
		bundle := NewMimeBundleBuilder().
			WithImageJPEG("jpegdata").
			Build()

		val, ok := bundle.Get("image/jpeg")
		assert.True(t, ok)
		assert.Equal(t, "jpegdata", val)
	})

	t.Run("adds application/json", func(t *testing.T) {
		data := map[string]any{"key": "value"}
		bundle := NewMimeBundleBuilder().
			WithApplicationJSON(data).
			Build()

		val, ok := bundle.Get("application/json")
		assert.True(t, ok)
		assert.Equal(t, data, val)
	})

	t.Run("reset clears state", func(t *testing.T) {
		builder := NewMimeBundleBuilder().
			WithTextPlain("hello")

		builder.Reset()
		bundle := builder.Build()

		assert.Nil(t, bundle.Data())
	})

	t.Run("build creates defensive copy", func(t *testing.T) {
		builder := NewMimeBundleBuilder().
			WithTextPlain("hello")

		bundle := builder.Build()

		// Add more data to builder
		builder.WithTextHTML("<b>world</b>")

		// Original bundle should be unaffected
		_, ok := bundle.Get("text/html")
		assert.False(t, ok)
	})
}
