package nbformat

// NotebookBuilder provides a fluent interface for constructing notebooks.
// This builder allows efficient incremental construction with minimal allocations.
type NotebookBuilder struct {
	nbformat      int
	nbformatMinor int
	metadata      NotebookMetadata
	cells         []Cell
}

// NewNotebookBuilder creates a new NotebookBuilder with default format version.
func NewNotebookBuilder() *NotebookBuilder {
	return &NotebookBuilder{
		nbformat:      NBFormat,
		nbformatMinor: NBFormatMinor,
	}
}

// WithNBFormat sets the notebook format version.
func (b *NotebookBuilder) WithNBFormat(nbformat, nbformatMinor int) *NotebookBuilder {
	b.nbformat = nbformat
	b.nbformatMinor = nbformatMinor
	return b
}

// WithMetadata sets the notebook metadata.
func (b *NotebookBuilder) WithMetadata(metadata NotebookMetadata) *NotebookBuilder {
	b.metadata = metadata
	return b
}

// WithKernelSpec sets the kernel specification in the metadata.
func (b *NotebookBuilder) WithKernelSpec(name, displayName string) *NotebookBuilder {
	b.metadata = b.metadata.WithKernelSpec(NewKernelSpec(name, displayName))
	return b
}

// WithLanguageInfo sets the language information in the metadata.
func (b *NotebookBuilder) WithLanguageInfo(name string) *NotebookBuilder {
	b.metadata = b.metadata.WithLanguageInfo(NewLanguageInfo(name))
	return b
}

// WithTitle sets the title in the metadata.
func (b *NotebookBuilder) WithTitle(title string) *NotebookBuilder {
	b.metadata = b.metadata.WithTitle(title)
	return b
}

// AddCell adds a cell to the notebook.
func (b *NotebookBuilder) AddCell(cell Cell) *NotebookBuilder {
	b.cells = append(b.cells, cell)
	return b
}

// AddCells adds multiple cells to the notebook.
func (b *NotebookBuilder) AddCells(cells ...Cell) *NotebookBuilder {
	b.cells = append(b.cells, cells...)
	return b
}

// AddCodeCell adds a code cell with the given source.
func (b *NotebookBuilder) AddCodeCell(source string) *NotebookBuilder {
	b.cells = append(b.cells, NewCodeCell(source))
	return b
}

// AddCodeCellWithID adds a code cell with the given ID and source.
func (b *NotebookBuilder) AddCodeCellWithID(id, source string) *NotebookBuilder {
	b.cells = append(b.cells, NewCodeCell(source).WithID(id))
	return b
}

// AddMarkdownCell adds a markdown cell with the given source.
func (b *NotebookBuilder) AddMarkdownCell(source string) *NotebookBuilder {
	b.cells = append(b.cells, NewMarkdownCell(source))
	return b
}

// AddMarkdownCellWithID adds a markdown cell with the given ID and source.
func (b *NotebookBuilder) AddMarkdownCellWithID(id, source string) *NotebookBuilder {
	b.cells = append(b.cells, NewMarkdownCell(source).WithID(id))
	return b
}

// AddRawCell adds a raw cell with the given source.
func (b *NotebookBuilder) AddRawCell(source string) *NotebookBuilder {
	b.cells = append(b.cells, NewRawCell(source))
	return b
}

// AddRawCellWithID adds a raw cell with the given ID and source.
func (b *NotebookBuilder) AddRawCellWithID(id, source string) *NotebookBuilder {
	b.cells = append(b.cells, NewRawCell(source).WithID(id))
	return b
}

// Build creates the final immutable Notebook.
func (b *NotebookBuilder) Build() Notebook {
	var cells []Cell
	if len(b.cells) > 0 {
		cells = make([]Cell, len(b.cells))
		copy(cells, b.cells)
	}
	return Notebook{
		nbformat:      b.nbformat,
		nbformatMinor: b.nbformatMinor,
		metadata:      b.metadata,
		cells:         cells,
	}
}

// Reset clears the builder for reuse.
func (b *NotebookBuilder) Reset() *NotebookBuilder {
	b.nbformat = NBFormat
	b.nbformatMinor = NBFormatMinor
	b.metadata = NotebookMetadata{}
	b.cells = b.cells[:0]
	return b
}

// CodeCellBuilder provides a fluent interface for constructing code cells.
type CodeCellBuilder struct {
	id             string
	source         string
	metadata       CellMetadata
	executionCount *int
	outputs        []Output
}

// NewCodeCellBuilder creates a new CodeCellBuilder.
func NewCodeCellBuilder() *CodeCellBuilder {
	return &CodeCellBuilder{}
}

// WithID sets the cell ID.
func (b *CodeCellBuilder) WithID(id string) *CodeCellBuilder {
	b.id = id
	return b
}

// WithSource sets the cell source.
func (b *CodeCellBuilder) WithSource(source string) *CodeCellBuilder {
	b.source = source
	return b
}

// WithMetadata sets the cell metadata.
func (b *CodeCellBuilder) WithMetadata(metadata CellMetadata) *CodeCellBuilder {
	b.metadata = metadata
	return b
}

// WithExecutionCount sets the execution count.
func (b *CodeCellBuilder) WithExecutionCount(count int) *CodeCellBuilder {
	b.executionCount = &count
	return b
}

// AddOutput adds an output to the cell.
func (b *CodeCellBuilder) AddOutput(output Output) *CodeCellBuilder {
	b.outputs = append(b.outputs, output)
	return b
}

// AddStreamOutput adds a stream output to the cell.
func (b *CodeCellBuilder) AddStreamOutput(name StreamName, text string) *CodeCellBuilder {
	b.outputs = append(b.outputs, NewStreamOutput(name, text))
	return b
}

// AddStdoutOutput adds a stdout output to the cell.
func (b *CodeCellBuilder) AddStdoutOutput(text string) *CodeCellBuilder {
	b.outputs = append(b.outputs, NewStdoutOutput(text))
	return b
}

// AddStderrOutput adds a stderr output to the cell.
func (b *CodeCellBuilder) AddStderrOutput(text string) *CodeCellBuilder {
	b.outputs = append(b.outputs, NewStderrOutput(text))
	return b
}

// AddErrorOutput adds an error output to the cell.
func (b *CodeCellBuilder) AddErrorOutput(ename, evalue string, traceback []string) *CodeCellBuilder {
	b.outputs = append(b.outputs, NewErrorOutput(ename, evalue, traceback))
	return b
}

// AddDisplayDataOutput adds a display data output to the cell.
func (b *CodeCellBuilder) AddDisplayDataOutput(data MimeBundle) *CodeCellBuilder {
	b.outputs = append(b.outputs, NewDisplayDataOutput(data))
	return b
}

// AddExecuteResultOutput adds an execute result output to the cell.
func (b *CodeCellBuilder) AddExecuteResultOutput(executionCount int, data MimeBundle) *CodeCellBuilder {
	b.outputs = append(b.outputs, NewExecuteResultOutput(executionCount, data))
	return b
}

// Build creates the final immutable CodeCell.
func (b *CodeCellBuilder) Build() CodeCell {
	var outputs []Output
	if len(b.outputs) > 0 {
		outputs = make([]Output, len(b.outputs))
		copy(outputs, b.outputs)
	}
	return CodeCell{
		id:             b.id,
		source:         b.source,
		metadata:       b.metadata,
		executionCount: b.executionCount,
		outputs:        outputs,
	}
}

// Reset clears the builder for reuse.
func (b *CodeCellBuilder) Reset() *CodeCellBuilder {
	b.id = ""
	b.source = ""
	b.metadata = CellMetadata{}
	b.executionCount = nil
	b.outputs = b.outputs[:0]
	return b
}

// MarkdownCellBuilder provides a fluent interface for constructing markdown cells.
type MarkdownCellBuilder struct {
	id          string
	source      string
	metadata    CellMetadata
	attachments map[string]MimeBundle
}

// NewMarkdownCellBuilder creates a new MarkdownCellBuilder.
func NewMarkdownCellBuilder() *MarkdownCellBuilder {
	return &MarkdownCellBuilder{}
}

// WithID sets the cell ID.
func (b *MarkdownCellBuilder) WithID(id string) *MarkdownCellBuilder {
	b.id = id
	return b
}

// WithSource sets the cell source.
func (b *MarkdownCellBuilder) WithSource(source string) *MarkdownCellBuilder {
	b.source = source
	return b
}

// WithMetadata sets the cell metadata.
func (b *MarkdownCellBuilder) WithMetadata(metadata CellMetadata) *MarkdownCellBuilder {
	b.metadata = metadata
	return b
}

// AddAttachment adds an attachment to the cell.
func (b *MarkdownCellBuilder) AddAttachment(name string, data MimeBundle) *MarkdownCellBuilder {
	if b.attachments == nil {
		b.attachments = make(map[string]MimeBundle)
	}
	b.attachments[name] = data.clone()
	return b
}

// Build creates the final immutable MarkdownCell.
func (b *MarkdownCellBuilder) Build() MarkdownCell {
	var attachments map[string]MimeBundle
	if len(b.attachments) > 0 {
		attachments = make(map[string]MimeBundle, len(b.attachments))
		for k, v := range b.attachments {
			attachments[k] = v.clone()
		}
	}
	return MarkdownCell{
		id:          b.id,
		source:      b.source,
		metadata:    b.metadata,
		attachments: attachments,
	}
}

// Reset clears the builder for reuse.
func (b *MarkdownCellBuilder) Reset() *MarkdownCellBuilder {
	b.id = ""
	b.source = ""
	b.metadata = CellMetadata{}
	b.attachments = nil
	return b
}

// RawCellBuilder provides a fluent interface for constructing raw cells.
type RawCellBuilder struct {
	id          string
	source      string
	metadata    CellMetadata
	attachments map[string]MimeBundle
}

// NewRawCellBuilder creates a new RawCellBuilder.
func NewRawCellBuilder() *RawCellBuilder {
	return &RawCellBuilder{}
}

// WithID sets the cell ID.
func (b *RawCellBuilder) WithID(id string) *RawCellBuilder {
	b.id = id
	return b
}

// WithSource sets the cell source.
func (b *RawCellBuilder) WithSource(source string) *RawCellBuilder {
	b.source = source
	return b
}

// WithMetadata sets the cell metadata.
func (b *RawCellBuilder) WithMetadata(metadata CellMetadata) *RawCellBuilder {
	b.metadata = metadata
	return b
}

// AddAttachment adds an attachment to the cell.
func (b *RawCellBuilder) AddAttachment(name string, data MimeBundle) *RawCellBuilder {
	if b.attachments == nil {
		b.attachments = make(map[string]MimeBundle)
	}
	b.attachments[name] = data.clone()
	return b
}

// Build creates the final immutable RawCell.
func (b *RawCellBuilder) Build() RawCell {
	var attachments map[string]MimeBundle
	if len(b.attachments) > 0 {
		attachments = make(map[string]MimeBundle, len(b.attachments))
		for k, v := range b.attachments {
			attachments[k] = v.clone()
		}
	}
	return RawCell{
		id:          b.id,
		source:      b.source,
		metadata:    b.metadata,
		attachments: attachments,
	}
}

// Reset clears the builder for reuse.
func (b *RawCellBuilder) Reset() *RawCellBuilder {
	b.id = ""
	b.source = ""
	b.metadata = CellMetadata{}
	b.attachments = nil
	return b
}

// MimeBundleBuilder provides a fluent interface for constructing MimeBundles.
type MimeBundleBuilder struct {
	data map[string]any
}

// NewMimeBundleBuilder creates a new MimeBundleBuilder.
func NewMimeBundleBuilder() *MimeBundleBuilder {
	return &MimeBundleBuilder{}
}

// WithData adds data for a MIME type.
func (b *MimeBundleBuilder) WithData(mimeType string, data any) *MimeBundleBuilder {
	if b.data == nil {
		b.data = make(map[string]any)
	}
	b.data[mimeType] = data
	return b
}

// WithTextPlain adds text/plain data.
func (b *MimeBundleBuilder) WithTextPlain(text string) *MimeBundleBuilder {
	return b.WithData("text/plain", text)
}

// WithTextHTML adds text/html data.
func (b *MimeBundleBuilder) WithTextHTML(html string) *MimeBundleBuilder {
	return b.WithData("text/html", html)
}

// WithImagePNG adds image/png data (base64 encoded).
func (b *MimeBundleBuilder) WithImagePNG(data string) *MimeBundleBuilder {
	return b.WithData("image/png", data)
}

// WithImageJPEG adds image/jpeg data (base64 encoded).
func (b *MimeBundleBuilder) WithImageJPEG(data string) *MimeBundleBuilder {
	return b.WithData("image/jpeg", data)
}

// WithApplicationJSON adds application/json data.
func (b *MimeBundleBuilder) WithApplicationJSON(data any) *MimeBundleBuilder {
	return b.WithData("application/json", data)
}

// Build creates the final immutable MimeBundle.
func (b *MimeBundleBuilder) Build() MimeBundle {
	if len(b.data) == 0 {
		return MimeBundle{}
	}
	data := make(map[string]any, len(b.data))
	for k, v := range b.data {
		data[k] = v
	}
	return MimeBundle{data: data}
}

// Reset clears the builder for reuse.
func (b *MimeBundleBuilder) Reset() *MimeBundleBuilder {
	b.data = nil
	return b
}
