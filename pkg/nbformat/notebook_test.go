package nbformat

import (
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestNotebook(t *testing.T) {
	t.Run("NewNotebook creates empty notebook with current format", func(t *testing.T) {
		notebook := NewNotebook()
		assert.Equal(t, NBFormat, notebook.NBFormat())
		assert.Equal(t, NBFormatMinor, notebook.NBFormatMinor())
		assert.Nil(t, notebook.Cells())
		assert.Equal(t, 0, notebook.CellCount())
	})

	t.Run("NewNotebookWithVersion creates notebook with specified version", func(t *testing.T) {
		notebook := NewNotebookWithVersion(4, 4)
		assert.Equal(t, 4, notebook.NBFormat())
		assert.Equal(t, 4, notebook.NBFormatMinor())
	})

	t.Run("WithMetadata sets metadata immutably", func(t *testing.T) {
		original := NewNotebook()
		meta := NewNotebookMetadata().WithTitle("My Notebook")
		modified := original.WithMetadata(meta)

		assert.Empty(t, original.Metadata().Title())
		assert.Equal(t, "My Notebook", modified.Metadata().Title())
	})

	t.Run("WithCells creates defensive copy", func(t *testing.T) {
		cells := []Cell{NewCodeCell("x = 1"), NewMarkdownCell("# Title")}
		notebook := NewNotebook().WithCells(cells)

		// Modify original slice
		cells[0] = NewCodeCell("y = 2")

		// Notebook should be unaffected
		assert.Equal(t, "x = 1", notebook.Cells()[0].Source())
	})

	t.Run("Cells returns defensive copy", func(t *testing.T) {
		notebook := NewNotebook().WithCells([]Cell{NewCodeCell("x = 1")})

		cells := notebook.Cells()
		cells[0] = NewCodeCell("y = 2")

		// Original notebook should be unaffected
		assert.Equal(t, "x = 1", notebook.Cells()[0].Source())
	})

	t.Run("AddCell appends cell immutably", func(t *testing.T) {
		original := NewNotebook()
		modified := original.AddCell(NewCodeCell("x = 1"))

		assert.Nil(t, original.Cells())
		require.Len(t, modified.Cells(), 1)
		assert.Equal(t, "x = 1", modified.Cells()[0].Source())
	})

	t.Run("InsertCell inserts at correct position", func(t *testing.T) {
		notebook := NewNotebook().
			AddCell(NewCodeCell("cell 0")).
			AddCell(NewCodeCell("cell 2"))

		modified := notebook.InsertCell(1, NewCodeCell("cell 1"))

		require.Len(t, modified.Cells(), 3)
		assert.Equal(t, "cell 0", modified.Cells()[0].Source())
		assert.Equal(t, "cell 1", modified.Cells()[1].Source())
		assert.Equal(t, "cell 2", modified.Cells()[2].Source())
	})

	t.Run("InsertCell at beginning", func(t *testing.T) {
		notebook := NewNotebook().AddCell(NewCodeCell("cell 1"))
		modified := notebook.InsertCell(0, NewCodeCell("cell 0"))

		require.Len(t, modified.Cells(), 2)
		assert.Equal(t, "cell 0", modified.Cells()[0].Source())
		assert.Equal(t, "cell 1", modified.Cells()[1].Source())
	})

	t.Run("InsertCell beyond end appends", func(t *testing.T) {
		notebook := NewNotebook().AddCell(NewCodeCell("cell 0"))
		modified := notebook.InsertCell(100, NewCodeCell("cell 1"))

		require.Len(t, modified.Cells(), 2)
		assert.Equal(t, "cell 1", modified.Cells()[1].Source())
	})

	t.Run("RemoveCell removes at correct position", func(t *testing.T) {
		notebook := NewNotebook().
			AddCell(NewCodeCell("cell 0")).
			AddCell(NewCodeCell("cell 1")).
			AddCell(NewCodeCell("cell 2"))

		modified := notebook.RemoveCell(1)

		require.Len(t, modified.Cells(), 2)
		assert.Equal(t, "cell 0", modified.Cells()[0].Source())
		assert.Equal(t, "cell 2", modified.Cells()[1].Source())
	})

	t.Run("RemoveCell with invalid index returns unchanged", func(t *testing.T) {
		notebook := NewNotebook().AddCell(NewCodeCell("cell 0"))

		modified := notebook.RemoveCell(-1)
		assert.Len(t, modified.Cells(), 1)

		modified = notebook.RemoveCell(100)
		assert.Len(t, modified.Cells(), 1)
	})

	t.Run("ReplaceCell replaces at correct position", func(t *testing.T) {
		notebook := NewNotebook().
			AddCell(NewCodeCell("cell 0")).
			AddCell(NewCodeCell("cell 1"))

		modified := notebook.ReplaceCell(0, NewMarkdownCell("# Replaced"))

		require.Len(t, modified.Cells(), 2)
		assert.Equal(t, CellTypeMarkdown, modified.Cells()[0].CellType())
		assert.Equal(t, "# Replaced", modified.Cells()[0].Source())
	})

	t.Run("ReplaceCell with invalid index returns unchanged", func(t *testing.T) {
		notebook := NewNotebook().AddCell(NewCodeCell("cell 0"))

		modified := notebook.ReplaceCell(-1, NewCodeCell("new"))
		assert.Equal(t, "cell 0", modified.Cells()[0].Source())

		modified = notebook.ReplaceCell(100, NewCodeCell("new"))
		assert.Equal(t, "cell 0", modified.Cells()[0].Source())
	})

	t.Run("Cell returns cell at index", func(t *testing.T) {
		notebook := NewNotebook().
			AddCell(NewCodeCell("cell 0")).
			AddCell(NewMarkdownCell("cell 1"))

		assert.Equal(t, "cell 0", notebook.Cell(0).Source())
		assert.Equal(t, "cell 1", notebook.Cell(1).Source())
	})

	t.Run("WithNBFormat sets version immutably", func(t *testing.T) {
		original := NewNotebook()
		modified := original.WithNBFormat(4, 4)

		assert.Equal(t, NBFormatMinor, original.NBFormatMinor())
		assert.Equal(t, 4, modified.NBFormatMinor())
	})
}

func TestNotebookMetadata(t *testing.T) {
	t.Run("NewNotebookMetadata creates empty metadata", func(t *testing.T) {
		meta := NewNotebookMetadata()
		assert.Nil(t, meta.KernelSpec())
		assert.Nil(t, meta.LanguageInfo())
		assert.Empty(t, meta.Title())
		assert.Nil(t, meta.Authors())
		assert.Nil(t, meta.Custom())
	})

	t.Run("WithKernelSpec sets kernel spec", func(t *testing.T) {
		meta := NewNotebookMetadata().WithKernelSpec(NewKernelSpec("python3", "Python 3"))

		require.NotNil(t, meta.KernelSpec())
		assert.Equal(t, "python3", meta.KernelSpec().Name())
		assert.Equal(t, "Python 3", meta.KernelSpec().DisplayName())
	})

	t.Run("WithLanguageInfo sets language info", func(t *testing.T) {
		meta := NewNotebookMetadata().WithLanguageInfo(NewLanguageInfo("python"))

		require.NotNil(t, meta.LanguageInfo())
		assert.Equal(t, "python", meta.LanguageInfo().Name())
	})

	t.Run("WithTitle sets title", func(t *testing.T) {
		original := NewNotebookMetadata()
		modified := original.WithTitle("My Notebook")

		assert.Empty(t, original.Title())
		assert.Equal(t, "My Notebook", modified.Title())
	})

	t.Run("WithAuthors creates defensive copy", func(t *testing.T) {
		authors := []Author{NewAuthor("Alice"), NewAuthor("Bob")}
		meta := NewNotebookMetadata().WithAuthors(authors)

		// Modify original slice
		authors[0] = NewAuthor("Charlie")

		// Metadata should be unaffected
		assert.Equal(t, "Alice", meta.Authors()[0].Name())
	})

	t.Run("Authors returns defensive copy", func(t *testing.T) {
		meta := NewNotebookMetadata().WithAuthors([]Author{NewAuthor("Alice")})

		authors := meta.Authors()
		authors[0] = NewAuthor("Bob")

		// Original metadata should be unaffected
		assert.Equal(t, "Alice", meta.Authors()[0].Name())
	})

	t.Run("WithCustom adds custom fields", func(t *testing.T) {
		meta := NewNotebookMetadata().
			WithCustom("custom_key", "custom_value").
			WithCustom("number", 42)

		custom := meta.Custom()
		assert.Equal(t, "custom_value", custom["custom_key"])
		assert.Equal(t, 42, custom["number"])
	})
}

func TestKernelSpec(t *testing.T) {
	t.Run("NewKernelSpec creates kernel spec", func(t *testing.T) {
		ks := NewKernelSpec("python3", "Python 3")
		assert.Equal(t, "python3", ks.Name())
		assert.Equal(t, "Python 3", ks.DisplayName())
		assert.Empty(t, ks.Language())
	})

	t.Run("With methods create new instances", func(t *testing.T) {
		original := NewKernelSpec("python3", "Python 3")
		modified := original.
			WithName("ir").
			WithDisplayName("IRkernel").
			WithLanguage("R")

		assert.Equal(t, "python3", original.Name())
		assert.Equal(t, "ir", modified.Name())
		assert.Equal(t, "IRkernel", modified.DisplayName())
		assert.Equal(t, "R", modified.Language())
	})
}

func TestLanguageInfo(t *testing.T) {
	t.Run("NewLanguageInfo creates language info", func(t *testing.T) {
		li := NewLanguageInfo("python")
		assert.Equal(t, "python", li.Name())
		assert.Empty(t, li.Version())
		assert.Empty(t, li.MimeType())
		assert.Empty(t, li.FileExtension())
	})

	t.Run("With methods create new instances", func(t *testing.T) {
		original := NewLanguageInfo("python")
		modified := original.
			WithVersion("3.10.0").
			WithMimeType("text/x-python").
			WithFileExtension(".py").
			WithPygmentsLexer("ipython3").
			WithCodemirrorMode("python").
			WithNBConvertExporter("python")

		assert.Empty(t, original.Version())
		assert.Equal(t, "3.10.0", modified.Version())
		assert.Equal(t, "text/x-python", modified.MimeType())
		assert.Equal(t, ".py", modified.FileExtension())
		assert.Equal(t, "ipython3", modified.PygmentsLexer())
		assert.Equal(t, "python", modified.CodemirrorMode())
		assert.Equal(t, "python", modified.NBConvertExporter())
	})
}

func TestAuthor(t *testing.T) {
	t.Run("NewAuthor creates author", func(t *testing.T) {
		author := NewAuthor("Alice Smith")
		assert.Equal(t, "Alice Smith", author.Name())
	})

	t.Run("WithName sets name immutably", func(t *testing.T) {
		original := NewAuthor("Alice")
		modified := original.WithName("Bob")

		assert.Equal(t, "Alice", original.Name())
		assert.Equal(t, "Bob", modified.Name())
	})
}
