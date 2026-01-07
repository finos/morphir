package nbformat

import (
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestCodeCell(t *testing.T) {
	t.Run("NewCodeCell creates cell with source", func(t *testing.T) {
		cell := NewCodeCell("print('hello')")
		assert.Equal(t, CellTypeCode, cell.CellType())
		assert.Equal(t, "print('hello')", cell.Source())
		assert.Empty(t, cell.ID())
		assert.Nil(t, cell.ExecutionCount())
		assert.Nil(t, cell.Outputs())
	})

	t.Run("WithID sets ID immutably", func(t *testing.T) {
		original := NewCodeCell("x = 1")
		modified := original.WithID("cell-1")

		assert.Empty(t, original.ID())
		assert.Equal(t, "cell-1", modified.ID())
		assert.Equal(t, "x = 1", modified.Source())
	})

	t.Run("WithSource sets source immutably", func(t *testing.T) {
		original := NewCodeCell("x = 1")
		modified := original.WithSource("y = 2")

		assert.Equal(t, "x = 1", original.Source())
		assert.Equal(t, "y = 2", modified.Source())
	})

	t.Run("WithExecutionCount sets execution count", func(t *testing.T) {
		cell := NewCodeCell("x = 1").WithExecutionCount(5)

		require.NotNil(t, cell.ExecutionCount())
		assert.Equal(t, 5, *cell.ExecutionCount())
	})

	t.Run("WithOutputs creates defensive copy", func(t *testing.T) {
		outputs := []Output{NewStdoutOutput("hello")}
		cell := NewCodeCell("print('hello')").WithOutputs(outputs)

		// Modify original slice
		outputs[0] = NewStderrOutput("error")

		// Cell should be unaffected
		cellOutputs := cell.Outputs()
		require.Len(t, cellOutputs, 1)
		stream, ok := cellOutputs[0].(StreamOutput)
		require.True(t, ok)
		assert.Equal(t, StreamStdout, stream.Name())
	})

	t.Run("Outputs returns defensive copy", func(t *testing.T) {
		cell := NewCodeCell("x = 1").WithOutputs([]Output{NewStdoutOutput("hello")})

		outputs := cell.Outputs()
		outputs[0] = NewStderrOutput("error")

		// Original cell should be unaffected
		cellOutputs := cell.Outputs()
		stream, ok := cellOutputs[0].(StreamOutput)
		require.True(t, ok)
		assert.Equal(t, StreamStdout, stream.Name())
	})

	t.Run("AddOutput appends output immutably", func(t *testing.T) {
		original := NewCodeCell("x = 1")
		modified := original.AddOutput(NewStdoutOutput("hello"))

		assert.Nil(t, original.Outputs())
		require.Len(t, modified.Outputs(), 1)
	})

	t.Run("implements Cell interface", func(t *testing.T) {
		var cell Cell = NewCodeCell("x = 1")
		assert.Equal(t, CellTypeCode, cell.CellType())
	})
}

func TestMarkdownCell(t *testing.T) {
	t.Run("NewMarkdownCell creates cell with source", func(t *testing.T) {
		cell := NewMarkdownCell("# Title")
		assert.Equal(t, CellTypeMarkdown, cell.CellType())
		assert.Equal(t, "# Title", cell.Source())
		assert.Empty(t, cell.ID())
		assert.Nil(t, cell.Attachments())
	})

	t.Run("WithID sets ID immutably", func(t *testing.T) {
		original := NewMarkdownCell("# Title")
		modified := original.WithID("md-1")

		assert.Empty(t, original.ID())
		assert.Equal(t, "md-1", modified.ID())
	})

	t.Run("WithSource sets source immutably", func(t *testing.T) {
		original := NewMarkdownCell("# Title")
		modified := original.WithSource("## Subtitle")

		assert.Equal(t, "# Title", original.Source())
		assert.Equal(t, "## Subtitle", modified.Source())
	})

	t.Run("WithAttachments creates defensive copy", func(t *testing.T) {
		attachments := map[string]MimeBundle{
			"image.png": NewMimeBundle().WithData("image/png", "base64data"),
		}
		cell := NewMarkdownCell("![image](attachment:image.png)").WithAttachments(attachments)

		// Modify original map
		attachments["other.png"] = NewMimeBundle()

		// Cell should have only original attachment
		cellAttachments := cell.Attachments()
		assert.Len(t, cellAttachments, 1)
		assert.Contains(t, cellAttachments, "image.png")
	})

	t.Run("Attachments returns defensive copy", func(t *testing.T) {
		cell := NewMarkdownCell("content").WithAttachments(map[string]MimeBundle{
			"image.png": NewMimeBundle().WithData("image/png", "data"),
		})

		attachments := cell.Attachments()
		attachments["other.png"] = NewMimeBundle()

		// Original cell should be unaffected
		assert.Len(t, cell.Attachments(), 1)
	})

	t.Run("implements Cell interface", func(t *testing.T) {
		var cell Cell = NewMarkdownCell("# Title")
		assert.Equal(t, CellTypeMarkdown, cell.CellType())
	})
}

func TestRawCell(t *testing.T) {
	t.Run("NewRawCell creates cell with source", func(t *testing.T) {
		cell := NewRawCell("<html>")
		assert.Equal(t, CellTypeRaw, cell.CellType())
		assert.Equal(t, "<html>", cell.Source())
		assert.Empty(t, cell.ID())
		assert.Nil(t, cell.Attachments())
	})

	t.Run("WithID sets ID immutably", func(t *testing.T) {
		original := NewRawCell("<html>")
		modified := original.WithID("raw-1")

		assert.Empty(t, original.ID())
		assert.Equal(t, "raw-1", modified.ID())
	})

	t.Run("WithSource sets source immutably", func(t *testing.T) {
		original := NewRawCell("<html>")
		modified := original.WithSource("<body>")

		assert.Equal(t, "<html>", original.Source())
		assert.Equal(t, "<body>", modified.Source())
	})

	t.Run("implements Cell interface", func(t *testing.T) {
		var cell Cell = NewRawCell("<html>")
		assert.Equal(t, CellTypeRaw, cell.CellType())
	})
}

func TestCellMetadata(t *testing.T) {
	t.Run("NewCellMetadata creates empty metadata", func(t *testing.T) {
		meta := NewCellMetadata()
		assert.False(t, meta.Collapsed())
		assert.Equal(t, ScrolledUnset, meta.Scrolled())
		assert.Nil(t, meta.Deletable())
		assert.Nil(t, meta.Editable())
		assert.Empty(t, meta.Name())
		assert.Nil(t, meta.Tags())
		assert.Nil(t, meta.Custom())
	})

	t.Run("With methods create new instances", func(t *testing.T) {
		original := NewCellMetadata()
		modified := original.
			WithCollapsed(true).
			WithScrolled(ScrolledAuto).
			WithDeletable(false).
			WithEditable(true).
			WithName("my-cell").
			WithTags([]string{"important", "review"})

		// Original should be unchanged
		assert.False(t, original.Collapsed())

		// Modified should have new values
		assert.True(t, modified.Collapsed())
		assert.Equal(t, ScrolledAuto, modified.Scrolled())
		require.NotNil(t, modified.Deletable())
		assert.False(t, *modified.Deletable())
		require.NotNil(t, modified.Editable())
		assert.True(t, *modified.Editable())
		assert.Equal(t, "my-cell", modified.Name())
		assert.Equal(t, []string{"important", "review"}, modified.Tags())
	})

	t.Run("Tags creates defensive copy", func(t *testing.T) {
		tags := []string{"a", "b"}
		meta := NewCellMetadata().WithTags(tags)

		// Modify original slice
		tags[0] = "modified"

		// Metadata should be unaffected
		assert.Equal(t, []string{"a", "b"}, meta.Tags())
	})

	t.Run("Tags returns defensive copy", func(t *testing.T) {
		meta := NewCellMetadata().WithTags([]string{"a", "b"})

		tags := meta.Tags()
		tags[0] = "modified"

		// Original metadata should be unaffected
		assert.Equal(t, []string{"a", "b"}, meta.Tags())
	})

	t.Run("WithCustom adds custom fields", func(t *testing.T) {
		meta := NewCellMetadata().
			WithCustom("key1", "value1").
			WithCustom("key2", 42)

		custom := meta.Custom()
		assert.Equal(t, "value1", custom["key1"])
		assert.Equal(t, 42, custom["key2"])
	})
}

func TestMimeBundle(t *testing.T) {
	t.Run("NewMimeBundle creates empty bundle", func(t *testing.T) {
		bundle := NewMimeBundle()
		assert.Nil(t, bundle.Data())
	})

	t.Run("WithData adds MIME data", func(t *testing.T) {
		bundle := NewMimeBundle().
			WithData("text/plain", "hello").
			WithData("text/html", "<b>hello</b>")

		data := bundle.Data()
		assert.Equal(t, "hello", data["text/plain"])
		assert.Equal(t, "<b>hello</b>", data["text/html"])
	})

	t.Run("Get returns data for MIME type", func(t *testing.T) {
		bundle := NewMimeBundle().WithData("text/plain", "hello")

		val, ok := bundle.Get("text/plain")
		assert.True(t, ok)
		assert.Equal(t, "hello", val)

		val, ok = bundle.Get("text/html")
		assert.False(t, ok)
		assert.Nil(t, val)
	})

	t.Run("Data returns defensive copy", func(t *testing.T) {
		bundle := NewMimeBundle().WithData("text/plain", "hello")

		data := bundle.Data()
		data["text/plain"] = "modified"

		// Original bundle should be unaffected
		val, _ := bundle.Get("text/plain")
		assert.Equal(t, "hello", val)
	})
}

func TestJupyterCellMetadata(t *testing.T) {
	t.Run("default values", func(t *testing.T) {
		meta := JupyterCellMetadata{}
		assert.False(t, meta.SourceHidden())
		assert.False(t, meta.OutputsHidden())
		assert.False(t, meta.OutputsExceeds())
	})

	t.Run("With methods create new instances", func(t *testing.T) {
		original := JupyterCellMetadata{}
		modified := original.
			WithSourceHidden(true).
			WithOutputsHidden(true).
			WithOutputsExceeds(true)

		assert.False(t, original.SourceHidden())
		assert.True(t, modified.SourceHidden())
		assert.True(t, modified.OutputsHidden())
		assert.True(t, modified.OutputsExceeds())
	})
}
