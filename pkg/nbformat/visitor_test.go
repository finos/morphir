package nbformat

import (
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestMatchCell(t *testing.T) {
	t.Run("matches code cell", func(t *testing.T) {
		cell := NewCodeCell("x = 1")
		result, err := MatchCell(cell, CellCases[string]{
			Code:     func(c CodeCell) string { return "code: " + c.Source() },
			Markdown: func(c MarkdownCell) string { return "markdown" },
			Raw:      func(c RawCell) string { return "raw" },
		})

		require.NoError(t, err)
		assert.Equal(t, "code: x = 1", result)
	})

	t.Run("matches markdown cell", func(t *testing.T) {
		cell := NewMarkdownCell("# Title")
		result, err := MatchCell(cell, CellCases[string]{
			Code:     func(c CodeCell) string { return "code" },
			Markdown: func(c MarkdownCell) string { return "markdown: " + c.Source() },
			Raw:      func(c RawCell) string { return "raw" },
		})

		require.NoError(t, err)
		assert.Equal(t, "markdown: # Title", result)
	})

	t.Run("matches raw cell", func(t *testing.T) {
		cell := NewRawCell("<html>")
		result, err := MatchCell(cell, CellCases[string]{
			Code:     func(c CodeCell) string { return "code" },
			Markdown: func(c MarkdownCell) string { return "markdown" },
			Raw:      func(c RawCell) string { return "raw: " + c.Source() },
		})

		require.NoError(t, err)
		assert.Equal(t, "raw: <html>", result)
	})

	t.Run("returns error for nil handler", func(t *testing.T) {
		cell := NewCodeCell("x = 1")
		_, err := MatchCell(cell, CellCases[string]{
			Code:     nil,
			Markdown: func(c MarkdownCell) string { return "markdown" },
			Raw:      func(c RawCell) string { return "raw" },
		})

		assert.ErrorIs(t, err, ErrUnhandledCellType)
	})

	t.Run("returns error for nil cell", func(t *testing.T) {
		_, err := MatchCell[string](nil, CellCases[string]{
			Code:     func(c CodeCell) string { return "code" },
			Markdown: func(c MarkdownCell) string { return "markdown" },
			Raw:      func(c RawCell) string { return "raw" },
		})

		assert.ErrorIs(t, err, ErrUnhandledCellType)
	})
}

func TestMustMatchCell(t *testing.T) {
	t.Run("returns result on success", func(t *testing.T) {
		cell := NewCodeCell("x = 1")
		result := MustMatchCell(cell, CellCases[int]{
			Code:     func(c CodeCell) int { return 1 },
			Markdown: func(c MarkdownCell) int { return 2 },
			Raw:      func(c RawCell) int { return 3 },
		})

		assert.Equal(t, 1, result)
	})

	t.Run("panics on error", func(t *testing.T) {
		cell := NewCodeCell("x = 1")
		assert.Panics(t, func() {
			MustMatchCell(cell, CellCases[int]{
				Code:     nil,
				Markdown: func(c MarkdownCell) int { return 2 },
				Raw:      func(c RawCell) int { return 3 },
			})
		})
	})
}

type testCellVisitor struct{}

func (v testCellVisitor) VisitCodeCell(c CodeCell) string         { return "visited code" }
func (v testCellVisitor) VisitMarkdownCell(c MarkdownCell) string { return "visited markdown" }
func (v testCellVisitor) VisitRawCell(c RawCell) string           { return "visited raw" }

func TestAcceptCellVisitor(t *testing.T) {
	visitor := testCellVisitor{}

	t.Run("visits code cell", func(t *testing.T) {
		result, err := AcceptCellVisitor(NewCodeCell("x = 1"), visitor)
		require.NoError(t, err)
		assert.Equal(t, "visited code", result)
	})

	t.Run("visits markdown cell", func(t *testing.T) {
		result, err := AcceptCellVisitor(NewMarkdownCell("# Title"), visitor)
		require.NoError(t, err)
		assert.Equal(t, "visited markdown", result)
	})

	t.Run("visits raw cell", func(t *testing.T) {
		result, err := AcceptCellVisitor(NewRawCell("<html>"), visitor)
		require.NoError(t, err)
		assert.Equal(t, "visited raw", result)
	})

	t.Run("returns error for nil cell", func(t *testing.T) {
		_, err := AcceptCellVisitor[string](nil, visitor)
		assert.ErrorIs(t, err, ErrUnhandledCellType)
	})
}

func TestMatchOutput(t *testing.T) {
	t.Run("matches stream output", func(t *testing.T) {
		output := NewStdoutOutput("hello")
		result, err := MatchOutput(output, OutputCases[string]{
			Stream:        func(o StreamOutput) string { return "stream: " + o.Text() },
			DisplayData:   func(o DisplayDataOutput) string { return "display" },
			ExecuteResult: func(o ExecuteResultOutput) string { return "execute" },
			Error:         func(o ErrorOutput) string { return "error" },
		})

		require.NoError(t, err)
		assert.Equal(t, "stream: hello", result)
	})

	t.Run("matches display data output", func(t *testing.T) {
		output := NewDisplayDataOutput(NewMimeBundle().WithData("text/plain", "data"))
		result, err := MatchOutput(output, OutputCases[string]{
			Stream:        func(o StreamOutput) string { return "stream" },
			DisplayData:   func(o DisplayDataOutput) string { return "display" },
			ExecuteResult: func(o ExecuteResultOutput) string { return "execute" },
			Error:         func(o ErrorOutput) string { return "error" },
		})

		require.NoError(t, err)
		assert.Equal(t, "display", result)
	})

	t.Run("matches execute result output", func(t *testing.T) {
		output := NewExecuteResultOutput(1, NewMimeBundle())
		result, err := MatchOutput(output, OutputCases[string]{
			Stream:        func(o StreamOutput) string { return "stream" },
			DisplayData:   func(o DisplayDataOutput) string { return "display" },
			ExecuteResult: func(o ExecuteResultOutput) string { return "execute" },
			Error:         func(o ErrorOutput) string { return "error" },
		})

		require.NoError(t, err)
		assert.Equal(t, "execute", result)
	})

	t.Run("matches error output", func(t *testing.T) {
		output := NewErrorOutput("Error", "msg", nil)
		result, err := MatchOutput(output, OutputCases[string]{
			Stream:        func(o StreamOutput) string { return "stream" },
			DisplayData:   func(o DisplayDataOutput) string { return "display" },
			ExecuteResult: func(o ExecuteResultOutput) string { return "execute" },
			Error:         func(o ErrorOutput) string { return "error: " + o.Ename() },
		})

		require.NoError(t, err)
		assert.Equal(t, "error: Error", result)
	})

	t.Run("returns error for nil handler", func(t *testing.T) {
		output := NewStdoutOutput("hello")
		_, err := MatchOutput(output, OutputCases[string]{
			Stream:        nil,
			DisplayData:   func(o DisplayDataOutput) string { return "display" },
			ExecuteResult: func(o ExecuteResultOutput) string { return "execute" },
			Error:         func(o ErrorOutput) string { return "error" },
		})

		assert.ErrorIs(t, err, ErrUnhandledOutputType)
	})
}

func TestMustMatchOutput(t *testing.T) {
	t.Run("returns result on success", func(t *testing.T) {
		output := NewStdoutOutput("hello")
		result := MustMatchOutput(output, OutputCases[int]{
			Stream:        func(o StreamOutput) int { return 1 },
			DisplayData:   func(o DisplayDataOutput) int { return 2 },
			ExecuteResult: func(o ExecuteResultOutput) int { return 3 },
			Error:         func(o ErrorOutput) int { return 4 },
		})

		assert.Equal(t, 1, result)
	})

	t.Run("panics on error", func(t *testing.T) {
		output := NewStdoutOutput("hello")
		assert.Panics(t, func() {
			MustMatchOutput(output, OutputCases[int]{
				Stream:        nil,
				DisplayData:   func(o DisplayDataOutput) int { return 2 },
				ExecuteResult: func(o ExecuteResultOutput) int { return 3 },
				Error:         func(o ErrorOutput) int { return 4 },
			})
		})
	})
}

type testOutputVisitor struct{}

func (v testOutputVisitor) VisitStreamOutput(o StreamOutput) string               { return "stream" }
func (v testOutputVisitor) VisitDisplayDataOutput(o DisplayDataOutput) string     { return "display" }
func (v testOutputVisitor) VisitExecuteResultOutput(o ExecuteResultOutput) string { return "execute" }
func (v testOutputVisitor) VisitErrorOutput(o ErrorOutput) string                 { return "error" }

func TestAcceptOutputVisitor(t *testing.T) {
	visitor := testOutputVisitor{}

	t.Run("visits stream output", func(t *testing.T) {
		result, err := AcceptOutputVisitor(NewStdoutOutput("hello"), visitor)
		require.NoError(t, err)
		assert.Equal(t, "stream", result)
	})

	t.Run("visits display data output", func(t *testing.T) {
		result, err := AcceptOutputVisitor(NewDisplayDataOutput(NewMimeBundle()), visitor)
		require.NoError(t, err)
		assert.Equal(t, "display", result)
	})

	t.Run("visits execute result output", func(t *testing.T) {
		result, err := AcceptOutputVisitor(NewExecuteResultOutput(1, NewMimeBundle()), visitor)
		require.NoError(t, err)
		assert.Equal(t, "execute", result)
	})

	t.Run("visits error output", func(t *testing.T) {
		result, err := AcceptOutputVisitor(NewErrorOutput("Error", "msg", nil), visitor)
		require.NoError(t, err)
		assert.Equal(t, "error", result)
	})
}

func TestFoldCell(t *testing.T) {
	t.Run("folds code cell", func(t *testing.T) {
		cell := NewCodeCell("x = 1")
		fold := CellFold[struct{}, int]{
			Code:     func(acc int, c CodeCell) int { return acc + len(c.Source()) },
			Markdown: func(acc int, c MarkdownCell) int { return acc },
			Raw:      func(acc int, c RawCell) int { return acc },
		}

		result, err := FoldCell(0, cell, fold)
		require.NoError(t, err)
		assert.Equal(t, 5, result) // len("x = 1") = 5
	})

	t.Run("returns error for nil handler", func(t *testing.T) {
		cell := NewCodeCell("x = 1")
		fold := CellFold[struct{}, int]{
			Code:     nil,
			Markdown: func(acc int, c MarkdownCell) int { return acc },
			Raw:      func(acc int, c RawCell) int { return acc },
		}

		_, err := FoldCell(0, cell, fold)
		assert.ErrorIs(t, err, ErrUnhandledCellType)
	})
}

func TestFoldOutput(t *testing.T) {
	t.Run("folds stream output", func(t *testing.T) {
		output := NewStdoutOutput("hello world")
		fold := OutputFold[struct{}, int]{
			Stream:        func(acc int, o StreamOutput) int { return acc + len(o.Text()) },
			DisplayData:   func(acc int, o DisplayDataOutput) int { return acc },
			ExecuteResult: func(acc int, o ExecuteResultOutput) int { return acc },
			Error:         func(acc int, o ErrorOutput) int { return acc },
		}

		result, err := FoldOutput(0, output, fold)
		require.NoError(t, err)
		assert.Equal(t, 11, result) // len("hello world") = 11
	})

	t.Run("returns error for nil handler", func(t *testing.T) {
		output := NewStdoutOutput("hello")
		fold := OutputFold[struct{}, int]{
			Stream:        nil,
			DisplayData:   func(acc int, o DisplayDataOutput) int { return acc },
			ExecuteResult: func(acc int, o ExecuteResultOutput) int { return acc },
			Error:         func(acc int, o ErrorOutput) int { return acc },
		}

		_, err := FoldOutput(0, output, fold)
		assert.ErrorIs(t, err, ErrUnhandledOutputType)
	})
}
