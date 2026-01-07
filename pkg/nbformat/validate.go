package nbformat

import (
	"github.com/finos/morphir/pkg/nbformat/internal/schema"
)

// ValidationError represents a validation error.
type ValidationError = schema.ValidationError

// ValidationResult contains the results of notebook validation.
type ValidationResult struct {
	result schema.ValidationResult
}

// IsValid returns true if the notebook passed validation.
func (r ValidationResult) IsValid() bool {
	return r.result.IsValid()
}

// Errors returns all validation errors.
func (r ValidationResult) Errors() []ValidationError {
	return r.result.Errors
}

// Error returns an error if validation failed, nil otherwise.
func (r ValidationResult) Error() error {
	return r.result.Error()
}

// ValidateOptions configures validation behavior.
type ValidateOptions struct {
	// Strict enables strict validation.
	Strict bool
	// RequireCellIDs requires all cells to have IDs (nbformat 5.1+).
	RequireCellIDs bool
}

// Validate validates a notebook against the nbformat schema.
func Validate(nb Notebook) ValidationResult {
	return ValidateWithOptions(nb, ValidateOptions{})
}

// ValidateWithOptions validates a notebook with custom options.
func ValidateWithOptions(nb Notebook, opts ValidateOptions) ValidationResult {
	// Convert to schema types
	cells := make([]schema.CellData, 0, nb.CellCount())
	for i := 0; i < nb.CellCount(); i++ {
		cells = append(cells, cellToSchemaData(nb.Cell(i)))
	}

	nbData := schema.NotebookData{
		NBFormat:      nb.NBFormat(),
		NBFormatMinor: nb.NBFormatMinor(),
		Cells:         cells,
	}

	schemaOpts := schema.ValidateOptions{
		Strict:         opts.Strict,
		RequireCellIDs: opts.RequireCellIDs,
	}

	return ValidationResult{result: schema.ValidateNotebook(nbData, schemaOpts)}
}

// cellToSchemaData converts a Cell to schema.CellData for validation.
func cellToSchemaData(cell Cell) schema.CellData {
	data := schema.CellData{
		ID:       cell.ID(),
		CellType: string(cell.CellType()),
		Source:   cell.Source(),
	}

	if code, ok := cell.(CodeCell); ok {
		data.ExecutionCount = code.ExecutionCount()
		outputs := code.Outputs()
		data.Outputs = make([]schema.OutputData, 0, len(outputs))
		for _, output := range outputs {
			data.Outputs = append(data.Outputs, outputToSchemaData(output))
		}
	}

	if md, ok := cell.(MarkdownCell); ok {
		if att := md.Attachments(); len(att) > 0 {
			data.Attachments = make(map[string]any, len(att))
			for k, v := range att {
				data.Attachments[k] = v.Data()
			}
		}
	}

	if raw, ok := cell.(RawCell); ok {
		if att := raw.Attachments(); len(att) > 0 {
			data.Attachments = make(map[string]any, len(att))
			for k, v := range att {
				data.Attachments[k] = v.Data()
			}
		}
	}

	return data
}

// outputToSchemaData converts an Output to schema.OutputData for validation.
func outputToSchemaData(output Output) schema.OutputData {
	data := schema.OutputData{
		OutputType: string(output.OutputType()),
	}

	switch o := output.(type) {
	case StreamOutput:
		data.Name = string(o.Name())
		data.Text = o.Text()

	case DisplayDataOutput:
		data.Data = o.Data().Data()
		data.Metadata = o.Metadata().Data()

	case ExecuteResultOutput:
		ec := o.ExecutionCount()
		data.ExecutionCount = &ec
		data.Data = o.Data().Data()
		data.Metadata = o.Metadata().Data()

	case ErrorOutput:
		data.Ename = o.Ename()
		data.Evalue = o.Evalue()
		data.Traceback = o.Traceback()
	}

	return data
}

// IsValidCellType returns true if the cell type is valid.
func IsValidCellType(cellType CellType) bool {
	return schema.ValidateCellType(string(cellType))
}

// IsValidOutputType returns true if the output type is valid.
func IsValidOutputType(outputType OutputType) bool {
	return schema.ValidateOutputType(string(outputType))
}

// IsValidStreamName returns true if the stream name is valid.
func IsValidStreamName(name StreamName) bool {
	return schema.ValidateStreamName(string(name))
}
