package nbformat

import (
	"errors"
	"strings"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func createTestNotebook() Notebook {
	return NewNotebook().
		AddCell(NewCodeCell("x = 1")).
		AddCell(NewMarkdownCell("# Title")).
		AddCell(NewCodeCell("y = 2")).
		AddCell(NewRawCell("<html>")).
		AddCell(NewCodeCell("z = 3"))
}

func TestMapCells(t *testing.T) {
	t.Run("transforms all cells", func(t *testing.T) {
		notebook := createTestNotebook()

		result := MapCells(notebook, func(c Cell) Cell {
			if code, ok := c.(CodeCell); ok {
				return code.WithSource("modified: " + code.Source())
			}
			return c
		})

		cells := result.Cells()
		assert.Equal(t, "modified: x = 1", cells[0].Source())
		assert.Equal(t, "# Title", cells[1].Source()) // markdown unchanged
		assert.Equal(t, "modified: y = 2", cells[2].Source())
		assert.Equal(t, "<html>", cells[3].Source()) // raw unchanged
		assert.Equal(t, "modified: z = 3", cells[4].Source())
	})

	t.Run("handles empty notebook", func(t *testing.T) {
		notebook := NewNotebook()
		result := MapCells(notebook, func(c Cell) Cell {
			return c
		})
		assert.Nil(t, result.Cells())
	})
}

func TestMapCellsWithIndex(t *testing.T) {
	t.Run("provides index to transform function", func(t *testing.T) {
		notebook := NewNotebook().
			AddCell(NewCodeCell("cell 0")).
			AddCell(NewCodeCell("cell 1")).
			AddCell(NewCodeCell("cell 2"))

		result := MapCellsWithIndex(notebook, func(i int, c Cell) Cell {
			if code, ok := c.(CodeCell); ok {
				return code.WithSource(strings.Replace(code.Source(), "cell", "index", 1))
			}
			return c
		})

		cells := result.Cells()
		assert.Equal(t, "index 0", cells[0].Source())
		assert.Equal(t, "index 1", cells[1].Source())
		assert.Equal(t, "index 2", cells[2].Source())
	})
}

func TestMapCellsErr(t *testing.T) {
	t.Run("transforms all cells on success", func(t *testing.T) {
		notebook := createTestNotebook()

		result, err := MapCellsErr(notebook, func(c Cell) (Cell, error) {
			if code, ok := c.(CodeCell); ok {
				return code.WithSource("ok"), nil
			}
			return c, nil
		})

		require.NoError(t, err)
		assert.Equal(t, "ok", result.Cells()[0].Source())
	})

	t.Run("returns error on failure", func(t *testing.T) {
		notebook := createTestNotebook()
		testErr := errors.New("transform failed")

		_, err := MapCellsErr(notebook, func(c Cell) (Cell, error) {
			if c.Source() == "y = 2" {
				return nil, testErr
			}
			return c, nil
		})

		assert.ErrorIs(t, err, testErr)
	})
}

func TestFilterCells(t *testing.T) {
	t.Run("filters cells by predicate", func(t *testing.T) {
		notebook := createTestNotebook()

		result := FilterCells(notebook, func(c Cell) bool {
			return c.CellType() == CellTypeCode
		})

		cells := result.Cells()
		require.Len(t, cells, 3)
		assert.Equal(t, "x = 1", cells[0].Source())
		assert.Equal(t, "y = 2", cells[1].Source())
		assert.Equal(t, "z = 3", cells[2].Source())
	})

	t.Run("returns empty when no cells match", func(t *testing.T) {
		notebook := createTestNotebook()

		result := FilterCells(notebook, func(c Cell) bool {
			return false
		})

		assert.Nil(t, result.Cells())
	})

	t.Run("handles empty notebook", func(t *testing.T) {
		notebook := NewNotebook()
		result := FilterCells(notebook, func(c Cell) bool { return true })
		assert.Nil(t, result.Cells())
	})
}

func TestFilterCellsWithIndex(t *testing.T) {
	t.Run("filters using index", func(t *testing.T) {
		notebook := createTestNotebook()

		// Keep only even-indexed cells
		result := FilterCellsWithIndex(notebook, func(i int, c Cell) bool {
			return i%2 == 0
		})

		cells := result.Cells()
		require.Len(t, cells, 3) // indices 0, 2, 4
	})
}

func TestFoldCells(t *testing.T) {
	t.Run("accumulates over all cells", func(t *testing.T) {
		notebook := createTestNotebook()

		result := FoldCells(notebook, 0, func(acc int, c Cell) int {
			return acc + len(c.Source())
		})

		// "x = 1" + "# Title" + "y = 2" + "<html>" + "z = 3" = 5 + 7 + 5 + 6 + 5 = 28
		assert.Equal(t, 28, result)
	})

	t.Run("returns initial for empty notebook", func(t *testing.T) {
		notebook := NewNotebook()

		result := FoldCells(notebook, 42, func(acc int, c Cell) int {
			return acc + 1
		})

		assert.Equal(t, 42, result)
	})
}

func TestFoldCellsWithIndex(t *testing.T) {
	t.Run("provides index to fold function", func(t *testing.T) {
		notebook := NewNotebook().
			AddCell(NewCodeCell("a")).
			AddCell(NewCodeCell("b")).
			AddCell(NewCodeCell("c"))

		result := FoldCellsWithIndex(notebook, 0, func(acc int, i int, c Cell) int {
			return acc + i
		})

		assert.Equal(t, 3, result) // 0 + 1 + 2 = 3
	})
}

func TestFoldCellsErr(t *testing.T) {
	t.Run("accumulates on success", func(t *testing.T) {
		notebook := createTestNotebook()

		result, err := FoldCellsErr(notebook, 0, func(acc int, c Cell) (int, error) {
			return acc + 1, nil
		})

		require.NoError(t, err)
		assert.Equal(t, 5, result)
	})

	t.Run("returns error on failure", func(t *testing.T) {
		notebook := createTestNotebook()
		testErr := errors.New("fold failed")

		_, err := FoldCellsErr(notebook, 0, func(acc int, c Cell) (int, error) {
			if acc >= 2 {
				return 0, testErr
			}
			return acc + 1, nil
		})

		assert.ErrorIs(t, err, testErr)
	})
}

func TestForEachCell(t *testing.T) {
	t.Run("iterates over all cells", func(t *testing.T) {
		notebook := createTestNotebook()
		var sources []string

		ForEachCell(notebook, func(c Cell) {
			sources = append(sources, c.Source())
		})

		assert.Len(t, sources, 5)
	})
}

func TestForEachCellWithIndex(t *testing.T) {
	t.Run("provides indices", func(t *testing.T) {
		notebook := createTestNotebook()
		var indices []int

		ForEachCellWithIndex(notebook, func(i int, c Cell) {
			indices = append(indices, i)
		})

		assert.Equal(t, []int{0, 1, 2, 3, 4}, indices)
	})
}

func TestFindCell(t *testing.T) {
	t.Run("finds first matching cell", func(t *testing.T) {
		notebook := createTestNotebook()

		cell := FindCell(notebook, func(c Cell) bool {
			return c.CellType() == CellTypeMarkdown
		})

		require.NotNil(t, cell)
		assert.Equal(t, "# Title", cell.Source())
	})

	t.Run("returns nil when no cell matches", func(t *testing.T) {
		notebook := createTestNotebook()

		cell := FindCell(notebook, func(c Cell) bool {
			return c.Source() == "nonexistent"
		})

		assert.Nil(t, cell)
	})
}

func TestFindCellIndex(t *testing.T) {
	t.Run("finds index of first matching cell", func(t *testing.T) {
		notebook := createTestNotebook()

		index := FindCellIndex(notebook, func(c Cell) bool {
			return c.CellType() == CellTypeRaw
		})

		assert.Equal(t, 3, index)
	})

	t.Run("returns -1 when no cell matches", func(t *testing.T) {
		notebook := createTestNotebook()

		index := FindCellIndex(notebook, func(c Cell) bool {
			return false
		})

		assert.Equal(t, -1, index)
	})
}

func TestAllCells(t *testing.T) {
	t.Run("returns true when all cells match", func(t *testing.T) {
		notebook := NewNotebook().
			AddCell(NewCodeCell("a")).
			AddCell(NewCodeCell("b"))

		result := AllCells(notebook, func(c Cell) bool {
			return c.CellType() == CellTypeCode
		})

		assert.True(t, result)
	})

	t.Run("returns false when any cell doesn't match", func(t *testing.T) {
		notebook := createTestNotebook()

		result := AllCells(notebook, func(c Cell) bool {
			return c.CellType() == CellTypeCode
		})

		assert.False(t, result)
	})

	t.Run("returns true for empty notebook", func(t *testing.T) {
		notebook := NewNotebook()

		result := AllCells(notebook, func(c Cell) bool {
			return false
		})

		assert.True(t, result)
	})
}

func TestAnyCells(t *testing.T) {
	t.Run("returns true when any cell matches", func(t *testing.T) {
		notebook := createTestNotebook()

		result := AnyCells(notebook, func(c Cell) bool {
			return c.CellType() == CellTypeRaw
		})

		assert.True(t, result)
	})

	t.Run("returns false when no cells match", func(t *testing.T) {
		notebook := NewNotebook().
			AddCell(NewCodeCell("a")).
			AddCell(NewCodeCell("b"))

		result := AnyCells(notebook, func(c Cell) bool {
			return c.CellType() == CellTypeMarkdown
		})

		assert.False(t, result)
	})

	t.Run("returns false for empty notebook", func(t *testing.T) {
		notebook := NewNotebook()

		result := AnyCells(notebook, func(c Cell) bool {
			return true
		})

		assert.False(t, result)
	})
}

func TestCountCells(t *testing.T) {
	t.Run("counts matching cells", func(t *testing.T) {
		notebook := createTestNotebook()

		count := CountCells(notebook, func(c Cell) bool {
			return c.CellType() == CellTypeCode
		})

		assert.Equal(t, 3, count)
	})
}

func TestPartitionCells(t *testing.T) {
	t.Run("partitions cells correctly", func(t *testing.T) {
		notebook := createTestNotebook()

		code, notCode := PartitionCells(notebook, func(c Cell) bool {
			return c.CellType() == CellTypeCode
		})

		assert.Len(t, code, 3)
		assert.Len(t, notCode, 2)
	})
}

func TestCollectCodeCells(t *testing.T) {
	t.Run("collects only code cells", func(t *testing.T) {
		notebook := createTestNotebook()

		cells := CollectCodeCells(notebook)

		require.Len(t, cells, 3)
		assert.Equal(t, "x = 1", cells[0].Source())
		assert.Equal(t, "y = 2", cells[1].Source())
		assert.Equal(t, "z = 3", cells[2].Source())
	})
}

func TestCollectMarkdownCells(t *testing.T) {
	t.Run("collects only markdown cells", func(t *testing.T) {
		notebook := createTestNotebook()

		cells := CollectMarkdownCells(notebook)

		require.Len(t, cells, 1)
		assert.Equal(t, "# Title", cells[0].Source())
	})
}

func TestCollectRawCells(t *testing.T) {
	t.Run("collects only raw cells", func(t *testing.T) {
		notebook := createTestNotebook()

		cells := CollectRawCells(notebook)

		require.Len(t, cells, 1)
		assert.Equal(t, "<html>", cells[0].Source())
	})
}

func TestMapOutputs(t *testing.T) {
	t.Run("transforms outputs in code cell", func(t *testing.T) {
		cell := NewCodeCell("x = 1").
			AddOutput(NewStdoutOutput("hello")).
			AddOutput(NewStdoutOutput("world"))

		result := MapOutputs(cell, func(o Output) Output {
			if stream, ok := o.(StreamOutput); ok {
				return stream.WithText("transformed")
			}
			return o
		})

		code := result.(CodeCell)
		outputs := code.Outputs()
		require.Len(t, outputs, 2)
		assert.Equal(t, "transformed", outputs[0].(StreamOutput).Text())
		assert.Equal(t, "transformed", outputs[1].(StreamOutput).Text())
	})

	t.Run("returns non-code cell unchanged", func(t *testing.T) {
		cell := NewMarkdownCell("# Title")
		result := MapOutputs(cell, func(o Output) Output {
			return o
		})

		assert.Equal(t, cell.Source(), result.Source())
	})
}

func TestFilterOutputs(t *testing.T) {
	t.Run("filters outputs in code cell", func(t *testing.T) {
		cell := NewCodeCell("x = 1").
			AddOutput(NewStdoutOutput("keep")).
			AddOutput(NewStderrOutput("remove")).
			AddOutput(NewStdoutOutput("keep2"))

		result := FilterOutputs(cell, func(o Output) bool {
			if stream, ok := o.(StreamOutput); ok {
				return stream.Name() == StreamStdout
			}
			return true
		})

		code := result.(CodeCell)
		outputs := code.Outputs()
		require.Len(t, outputs, 2)
	})
}

func TestFoldOutputs(t *testing.T) {
	t.Run("folds outputs in code cell", func(t *testing.T) {
		cell := NewCodeCell("x = 1").
			AddOutput(NewStdoutOutput("abc")).
			AddOutput(NewStdoutOutput("de"))

		result := FoldOutputs(cell, 0, func(acc int, o Output) int {
			if stream, ok := o.(StreamOutput); ok {
				return acc + len(stream.Text())
			}
			return acc
		})

		assert.Equal(t, 5, result) // 3 + 2
	})

	t.Run("returns initial for non-code cell", func(t *testing.T) {
		cell := NewMarkdownCell("# Title")
		result := FoldOutputs(cell, 42, func(acc int, o Output) int {
			return acc + 1
		})
		assert.Equal(t, 42, result)
	})
}

func TestCollectStreamOutputs(t *testing.T) {
	t.Run("collects only stream outputs", func(t *testing.T) {
		cell := NewCodeCell("x = 1").
			AddOutput(NewStdoutOutput("hello")).
			AddOutput(NewErrorOutput("Error", "msg", nil)).
			AddOutput(NewStderrOutput("error"))

		outputs := CollectStreamOutputs(cell)

		require.Len(t, outputs, 2)
		assert.Equal(t, "hello", outputs[0].Text())
		assert.Equal(t, "error", outputs[1].Text())
	})

	t.Run("returns nil for non-code cell", func(t *testing.T) {
		cell := NewMarkdownCell("# Title")
		outputs := CollectStreamOutputs(cell)
		assert.Nil(t, outputs)
	})
}

func TestCollectErrorOutputs(t *testing.T) {
	t.Run("collects only error outputs", func(t *testing.T) {
		cell := NewCodeCell("x = 1").
			AddOutput(NewStdoutOutput("hello")).
			AddOutput(NewErrorOutput("Error1", "msg1", nil)).
			AddOutput(NewErrorOutput("Error2", "msg2", nil))

		outputs := CollectErrorOutputs(cell)

		require.Len(t, outputs, 2)
		assert.Equal(t, "Error1", outputs[0].Ename())
		assert.Equal(t, "Error2", outputs[1].Ename())
	})
}

func TestHasErrors(t *testing.T) {
	t.Run("returns true when notebook has error outputs", func(t *testing.T) {
		notebook := NewNotebook().
			AddCell(NewCodeCell("x = 1").AddOutput(NewStdoutOutput("ok"))).
			AddCell(NewCodeCell("y = 2").AddOutput(NewErrorOutput("Error", "msg", nil)))

		assert.True(t, HasErrors(notebook))
	})

	t.Run("returns false when notebook has no error outputs", func(t *testing.T) {
		notebook := NewNotebook().
			AddCell(NewCodeCell("x = 1").AddOutput(NewStdoutOutput("ok"))).
			AddCell(NewMarkdownCell("# Title"))

		assert.False(t, HasErrors(notebook))
	})
}

func TestClearOutputs(t *testing.T) {
	t.Run("clears all code cell outputs", func(t *testing.T) {
		notebook := NewNotebook().
			AddCell(NewCodeCell("x = 1").
				WithExecutionCount(5).
				AddOutput(NewStdoutOutput("hello"))).
			AddCell(NewMarkdownCell("# Title"))

		result := ClearOutputs(notebook)

		cells := result.Cells()
		code := cells[0].(CodeCell)
		assert.Nil(t, code.Outputs())
		assert.Equal(t, 0, *code.ExecutionCount())

		// Markdown unchanged
		assert.Equal(t, "# Title", cells[1].Source())
	})
}

func TestClearExecutionCounts(t *testing.T) {
	t.Run("clears execution counts but keeps outputs", func(t *testing.T) {
		notebook := NewNotebook().
			AddCell(NewCodeCell("x = 1").
				WithExecutionCount(5).
				AddOutput(NewStdoutOutput("hello")))

		result := ClearExecutionCounts(notebook)

		code := result.Cells()[0].(CodeCell)
		assert.Nil(t, code.ExecutionCount())
		require.Len(t, code.Outputs(), 1) // Output preserved
	})
}
