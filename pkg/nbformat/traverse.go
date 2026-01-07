package nbformat

// MapCells transforms all cells in a notebook using the provided function.
// Returns a new notebook with the transformed cells.
func MapCells(notebook Notebook, fn func(Cell) Cell) Notebook {
	cells := notebook.Cells()
	if len(cells) == 0 {
		return notebook
	}
	newCells := make([]Cell, len(cells))
	for i, cell := range cells {
		newCells[i] = fn(cell)
	}
	return notebook.WithCells(newCells)
}

// MapCellsWithIndex transforms all cells in a notebook using the provided function.
// The function receives both the cell and its index.
func MapCellsWithIndex(notebook Notebook, fn func(int, Cell) Cell) Notebook {
	cells := notebook.Cells()
	if len(cells) == 0 {
		return notebook
	}
	newCells := make([]Cell, len(cells))
	for i, cell := range cells {
		newCells[i] = fn(i, cell)
	}
	return notebook.WithCells(newCells)
}

// MapCellsErr transforms all cells in a notebook using the provided function.
// Returns an error if any transformation fails.
func MapCellsErr(notebook Notebook, fn func(Cell) (Cell, error)) (Notebook, error) {
	cells := notebook.Cells()
	if len(cells) == 0 {
		return notebook, nil
	}
	newCells := make([]Cell, len(cells))
	for i, cell := range cells {
		newCell, err := fn(cell)
		if err != nil {
			return Notebook{}, err
		}
		newCells[i] = newCell
	}
	return notebook.WithCells(newCells), nil
}

// FilterCells returns a new notebook containing only cells that satisfy the predicate.
func FilterCells(notebook Notebook, predicate func(Cell) bool) Notebook {
	cells := notebook.Cells()
	if len(cells) == 0 {
		return notebook
	}
	var newCells []Cell
	for _, cell := range cells {
		if predicate(cell) {
			newCells = append(newCells, cell)
		}
	}
	return notebook.WithCells(newCells)
}

// FilterCellsWithIndex returns a new notebook containing only cells that satisfy the predicate.
// The predicate receives both the cell and its index.
func FilterCellsWithIndex(notebook Notebook, predicate func(int, Cell) bool) Notebook {
	cells := notebook.Cells()
	if len(cells) == 0 {
		return notebook
	}
	var newCells []Cell
	for i, cell := range cells {
		if predicate(i, cell) {
			newCells = append(newCells, cell)
		}
	}
	return notebook.WithCells(newCells)
}

// FoldCells folds over all cells in a notebook, accumulating a result.
func FoldCells[R any](notebook Notebook, initial R, fn func(R, Cell) R) R {
	cells := notebook.Cells()
	acc := initial
	for _, cell := range cells {
		acc = fn(acc, cell)
	}
	return acc
}

// FoldCellsWithIndex folds over all cells in a notebook, accumulating a result.
// The function receives the accumulator, cell index, and cell.
func FoldCellsWithIndex[R any](notebook Notebook, initial R, fn func(R, int, Cell) R) R {
	cells := notebook.Cells()
	acc := initial
	for i, cell := range cells {
		acc = fn(acc, i, cell)
	}
	return acc
}

// FoldCellsErr folds over all cells in a notebook, accumulating a result.
// Returns an error if any fold operation fails.
func FoldCellsErr[R any](notebook Notebook, initial R, fn func(R, Cell) (R, error)) (R, error) {
	cells := notebook.Cells()
	acc := initial
	var err error
	for _, cell := range cells {
		acc, err = fn(acc, cell)
		if err != nil {
			return acc, err
		}
	}
	return acc, nil
}

// ForEachCell iterates over all cells in a notebook.
func ForEachCell(notebook Notebook, fn func(Cell)) {
	cells := notebook.Cells()
	for _, cell := range cells {
		fn(cell)
	}
}

// ForEachCellWithIndex iterates over all cells in a notebook with their indices.
func ForEachCellWithIndex(notebook Notebook, fn func(int, Cell)) {
	cells := notebook.Cells()
	for i, cell := range cells {
		fn(i, cell)
	}
}

// FindCell returns the first cell that satisfies the predicate.
// Returns nil if no cell is found.
func FindCell(notebook Notebook, predicate func(Cell) bool) Cell {
	cells := notebook.Cells()
	for _, cell := range cells {
		if predicate(cell) {
			return cell
		}
	}
	return nil
}

// FindCellIndex returns the index of the first cell that satisfies the predicate.
// Returns -1 if no cell is found.
func FindCellIndex(notebook Notebook, predicate func(Cell) bool) int {
	cells := notebook.Cells()
	for i, cell := range cells {
		if predicate(cell) {
			return i
		}
	}
	return -1
}

// AllCells returns true if all cells satisfy the predicate.
// Returns true for an empty notebook.
func AllCells(notebook Notebook, predicate func(Cell) bool) bool {
	cells := notebook.Cells()
	for _, cell := range cells {
		if !predicate(cell) {
			return false
		}
	}
	return true
}

// AnyCells returns true if any cell satisfies the predicate.
// Returns false for an empty notebook.
func AnyCells(notebook Notebook, predicate func(Cell) bool) bool {
	cells := notebook.Cells()
	for _, cell := range cells {
		if predicate(cell) {
			return true
		}
	}
	return false
}

// CountCells returns the number of cells that satisfy the predicate.
func CountCells(notebook Notebook, predicate func(Cell) bool) int {
	cells := notebook.Cells()
	count := 0
	for _, cell := range cells {
		if predicate(cell) {
			count++
		}
	}
	return count
}

// PartitionCells partitions cells into two groups based on the predicate.
// Returns (matching cells, non-matching cells).
func PartitionCells(notebook Notebook, predicate func(Cell) bool) ([]Cell, []Cell) {
	cells := notebook.Cells()
	var matching, nonMatching []Cell
	for _, cell := range cells {
		if predicate(cell) {
			matching = append(matching, cell)
		} else {
			nonMatching = append(nonMatching, cell)
		}
	}
	return matching, nonMatching
}

// CollectCodeCells returns all code cells from the notebook.
func CollectCodeCells(notebook Notebook) []CodeCell {
	var result []CodeCell
	for _, cell := range notebook.Cells() {
		if code, ok := cell.(CodeCell); ok {
			result = append(result, code)
		}
	}
	return result
}

// CollectMarkdownCells returns all markdown cells from the notebook.
func CollectMarkdownCells(notebook Notebook) []MarkdownCell {
	var result []MarkdownCell
	for _, cell := range notebook.Cells() {
		if md, ok := cell.(MarkdownCell); ok {
			result = append(result, md)
		}
	}
	return result
}

// CollectRawCells returns all raw cells from the notebook.
func CollectRawCells(notebook Notebook) []RawCell {
	var result []RawCell
	for _, cell := range notebook.Cells() {
		if raw, ok := cell.(RawCell); ok {
			result = append(result, raw)
		}
	}
	return result
}

// MapOutputs transforms all outputs in a code cell using the provided function.
// Returns the original cell unchanged for non-code cells.
func MapOutputs(cell Cell, fn func(Output) Output) Cell {
	code, ok := cell.(CodeCell)
	if !ok {
		return cell
	}
	outputs := code.Outputs()
	if len(outputs) == 0 {
		return cell
	}
	newOutputs := make([]Output, len(outputs))
	for i, output := range outputs {
		newOutputs[i] = fn(output)
	}
	return code.WithOutputs(newOutputs)
}

// FilterOutputs returns a new code cell containing only outputs that satisfy the predicate.
// Returns the original cell unchanged for non-code cells.
func FilterOutputs(cell Cell, predicate func(Output) bool) Cell {
	code, ok := cell.(CodeCell)
	if !ok {
		return cell
	}
	outputs := code.Outputs()
	if len(outputs) == 0 {
		return cell
	}
	var newOutputs []Output
	for _, output := range outputs {
		if predicate(output) {
			newOutputs = append(newOutputs, output)
		}
	}
	return code.WithOutputs(newOutputs)
}

// FoldOutputs folds over all outputs in a code cell.
// Returns the initial value unchanged for non-code cells.
func FoldOutputs[R any](cell Cell, initial R, fn func(R, Output) R) R {
	code, ok := cell.(CodeCell)
	if !ok {
		return initial
	}
	outputs := code.Outputs()
	acc := initial
	for _, output := range outputs {
		acc = fn(acc, output)
	}
	return acc
}

// CollectStreamOutputs returns all stream outputs from a code cell.
func CollectStreamOutputs(cell Cell) []StreamOutput {
	code, ok := cell.(CodeCell)
	if !ok {
		return nil
	}
	var result []StreamOutput
	for _, output := range code.Outputs() {
		if stream, ok := output.(StreamOutput); ok {
			result = append(result, stream)
		}
	}
	return result
}

// CollectErrorOutputs returns all error outputs from a code cell.
func CollectErrorOutputs(cell Cell) []ErrorOutput {
	code, ok := cell.(CodeCell)
	if !ok {
		return nil
	}
	var result []ErrorOutput
	for _, output := range code.Outputs() {
		if errOut, ok := output.(ErrorOutput); ok {
			result = append(result, errOut)
		}
	}
	return result
}

// HasErrors returns true if any code cell in the notebook has error outputs.
func HasErrors(notebook Notebook) bool {
	return AnyCells(notebook, func(cell Cell) bool {
		if code, ok := cell.(CodeCell); ok {
			for _, output := range code.Outputs() {
				if _, ok := output.(ErrorOutput); ok {
					return true
				}
			}
		}
		return false
	})
}

// ClearOutputs returns a new notebook with all code cell outputs cleared.
func ClearOutputs(notebook Notebook) Notebook {
	return MapCells(notebook, func(cell Cell) Cell {
		if code, ok := cell.(CodeCell); ok {
			return code.WithOutputs(nil).WithExecutionCount(0)
		}
		return cell
	})
}

// ClearExecutionCounts returns a new notebook with all execution counts cleared.
func ClearExecutionCounts(notebook Notebook) Notebook {
	return MapCells(notebook, func(cell Cell) Cell {
		if code, ok := cell.(CodeCell); ok {
			return CodeCell{
				id:       code.id,
				source:   code.source,
				metadata: code.metadata,
				outputs:  code.outputs,
				// executionCount is left nil
			}
		}
		return cell
	})
}
