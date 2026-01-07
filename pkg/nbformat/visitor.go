package nbformat

import "errors"

// ErrUnhandledCellType is returned when a cell type is not handled by a visitor.
var ErrUnhandledCellType = errors.New("unhandled cell type")

// ErrUnhandledOutputType is returned when an output type is not handled by a visitor.
var ErrUnhandledOutputType = errors.New("unhandled output type")

// CellCases provides handlers for each cell type variant.
// Used with [MatchCell] for exhaustive pattern matching.
type CellCases[R any] struct {
	Code     func(CodeCell) R
	Markdown func(MarkdownCell) R
	Raw      func(RawCell) R
}

// MatchCell performs exhaustive pattern matching on a cell.
// Returns an error if the cell type is not recognized or a handler is nil.
func MatchCell[R any](cell Cell, cases CellCases[R]) (R, error) {
	var zero R
	switch c := cell.(type) {
	case CodeCell:
		if cases.Code == nil {
			return zero, ErrUnhandledCellType
		}
		return cases.Code(c), nil
	case MarkdownCell:
		if cases.Markdown == nil {
			return zero, ErrUnhandledCellType
		}
		return cases.Markdown(c), nil
	case RawCell:
		if cases.Raw == nil {
			return zero, ErrUnhandledCellType
		}
		return cases.Raw(c), nil
	default:
		return zero, ErrUnhandledCellType
	}
}

// MustMatchCell performs exhaustive pattern matching on a cell.
// Panics if the cell type is not recognized or a handler is nil.
func MustMatchCell[R any](cell Cell, cases CellCases[R]) R {
	result, err := MatchCell(cell, cases)
	if err != nil {
		panic(err)
	}
	return result
}

// CellVisitor defines the visitor interface for cells.
type CellVisitor[R any] interface {
	VisitCodeCell(CodeCell) R
	VisitMarkdownCell(MarkdownCell) R
	VisitRawCell(RawCell) R
}

// AcceptCellVisitor applies a visitor to a cell.
// Returns an error if the cell type is not recognized.
func AcceptCellVisitor[R any](cell Cell, visitor CellVisitor[R]) (R, error) {
	var zero R
	switch c := cell.(type) {
	case CodeCell:
		return visitor.VisitCodeCell(c), nil
	case MarkdownCell:
		return visitor.VisitMarkdownCell(c), nil
	case RawCell:
		return visitor.VisitRawCell(c), nil
	default:
		return zero, ErrUnhandledCellType
	}
}

// OutputCases provides handlers for each output type variant.
// Used with [MatchOutput] for exhaustive pattern matching.
type OutputCases[R any] struct {
	Stream        func(StreamOutput) R
	DisplayData   func(DisplayDataOutput) R
	ExecuteResult func(ExecuteResultOutput) R
	Error         func(ErrorOutput) R
}

// MatchOutput performs exhaustive pattern matching on an output.
// Returns an error if the output type is not recognized or a handler is nil.
func MatchOutput[R any](output Output, cases OutputCases[R]) (R, error) {
	var zero R
	switch o := output.(type) {
	case StreamOutput:
		if cases.Stream == nil {
			return zero, ErrUnhandledOutputType
		}
		return cases.Stream(o), nil
	case DisplayDataOutput:
		if cases.DisplayData == nil {
			return zero, ErrUnhandledOutputType
		}
		return cases.DisplayData(o), nil
	case ExecuteResultOutput:
		if cases.ExecuteResult == nil {
			return zero, ErrUnhandledOutputType
		}
		return cases.ExecuteResult(o), nil
	case ErrorOutput:
		if cases.Error == nil {
			return zero, ErrUnhandledOutputType
		}
		return cases.Error(o), nil
	default:
		return zero, ErrUnhandledOutputType
	}
}

// MustMatchOutput performs exhaustive pattern matching on an output.
// Panics if the output type is not recognized or a handler is nil.
func MustMatchOutput[R any](output Output, cases OutputCases[R]) R {
	result, err := MatchOutput(output, cases)
	if err != nil {
		panic(err)
	}
	return result
}

// OutputVisitor defines the visitor interface for outputs.
type OutputVisitor[R any] interface {
	VisitStreamOutput(StreamOutput) R
	VisitDisplayDataOutput(DisplayDataOutput) R
	VisitExecuteResultOutput(ExecuteResultOutput) R
	VisitErrorOutput(ErrorOutput) R
}

// AcceptOutputVisitor applies a visitor to an output.
// Returns an error if the output type is not recognized.
func AcceptOutputVisitor[R any](output Output, visitor OutputVisitor[R]) (R, error) {
	var zero R
	switch o := output.(type) {
	case StreamOutput:
		return visitor.VisitStreamOutput(o), nil
	case DisplayDataOutput:
		return visitor.VisitDisplayDataOutput(o), nil
	case ExecuteResultOutput:
		return visitor.VisitExecuteResultOutput(o), nil
	case ErrorOutput:
		return visitor.VisitErrorOutput(o), nil
	default:
		return zero, ErrUnhandledOutputType
	}
}

// CellFold provides accumulators for folding over cells.
// Each handler receives the accumulator and returns the new value.
type CellFold[A any, R any] struct {
	Code     func(R, CodeCell) R
	Markdown func(R, MarkdownCell) R
	Raw      func(R, RawCell) R
}

// FoldCell folds a single cell into an accumulator.
func FoldCell[A any, R any](acc R, cell Cell, fold CellFold[A, R]) (R, error) {
	switch c := cell.(type) {
	case CodeCell:
		if fold.Code == nil {
			return acc, ErrUnhandledCellType
		}
		return fold.Code(acc, c), nil
	case MarkdownCell:
		if fold.Markdown == nil {
			return acc, ErrUnhandledCellType
		}
		return fold.Markdown(acc, c), nil
	case RawCell:
		if fold.Raw == nil {
			return acc, ErrUnhandledCellType
		}
		return fold.Raw(acc, c), nil
	default:
		return acc, ErrUnhandledCellType
	}
}

// OutputFold provides accumulators for folding over outputs.
type OutputFold[A any, R any] struct {
	Stream        func(R, StreamOutput) R
	DisplayData   func(R, DisplayDataOutput) R
	ExecuteResult func(R, ExecuteResultOutput) R
	Error         func(R, ErrorOutput) R
}

// FoldOutput folds a single output into an accumulator.
func FoldOutput[A any, R any](acc R, output Output, fold OutputFold[A, R]) (R, error) {
	switch o := output.(type) {
	case StreamOutput:
		if fold.Stream == nil {
			return acc, ErrUnhandledOutputType
		}
		return fold.Stream(acc, o), nil
	case DisplayDataOutput:
		if fold.DisplayData == nil {
			return acc, ErrUnhandledOutputType
		}
		return fold.DisplayData(acc, o), nil
	case ExecuteResultOutput:
		if fold.ExecuteResult == nil {
			return acc, ErrUnhandledOutputType
		}
		return fold.ExecuteResult(acc, o), nil
	case ErrorOutput:
		if fold.Error == nil {
			return acc, ErrUnhandledOutputType
		}
		return fold.Error(acc, o), nil
	default:
		return acc, ErrUnhandledOutputType
	}
}
