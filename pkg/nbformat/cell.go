package nbformat

// CellType represents the type of a notebook cell.
type CellType string

const (
	CellTypeCode     CellType = "code"
	CellTypeMarkdown CellType = "markdown"
	CellTypeRaw      CellType = "raw"
)

// Cell is a sealed interface representing a notebook cell.
// The only implementations are [CodeCell], [MarkdownCell], and [RawCell].
type Cell interface {
	// isCell is a marker method that seals the interface.
	isCell()

	// CellType returns the type of the cell.
	CellType() CellType

	// Source returns the cell's source content.
	// For code cells, this is the executable code.
	// For markdown cells, this is the markdown text.
	// For raw cells, this is the raw content.
	Source() string

	// Metadata returns the cell's metadata.
	Metadata() CellMetadata

	// ID returns the cell's unique identifier (nbformat 5.1+).
	// May be empty for older notebooks.
	ID() string
}

// CellMetadata contains metadata associated with a cell.
type CellMetadata struct {
	collapsed bool
	scrolled  ScrolledState
	deletable *bool
	editable  *bool
	name      string
	tags      []string
	jupyter   JupyterCellMetadata
	custom    map[string]any
}

// ScrolledState represents the scrolled state of a cell's output.
type ScrolledState int

const (
	ScrolledUnset ScrolledState = iota
	ScrolledTrue
	ScrolledFalse
	ScrolledAuto
)

// JupyterCellMetadata contains Jupyter-specific cell metadata.
type JupyterCellMetadata struct {
	sourceHidden   bool
	outputsHidden  bool
	outputsExceeds bool
}

// NewCellMetadata creates a new CellMetadata with default values.
func NewCellMetadata() CellMetadata {
	return CellMetadata{}
}

// Collapsed returns whether the cell is collapsed.
func (m CellMetadata) Collapsed() bool { return m.collapsed }

// Scrolled returns the scrolled state of the cell.
func (m CellMetadata) Scrolled() ScrolledState { return m.scrolled }

// Deletable returns whether the cell can be deleted.
// Returns nil if not set.
func (m CellMetadata) Deletable() *bool {
	if m.deletable == nil {
		return nil
	}
	v := *m.deletable
	return &v
}

// Editable returns whether the cell can be edited.
// Returns nil if not set.
func (m CellMetadata) Editable() *bool {
	if m.editable == nil {
		return nil
	}
	v := *m.editable
	return &v
}

// Name returns the cell's name.
func (m CellMetadata) Name() string { return m.name }

// Tags returns a copy of the cell's tags.
func (m CellMetadata) Tags() []string {
	if len(m.tags) == 0 {
		return nil
	}
	result := make([]string, len(m.tags))
	copy(result, m.tags)
	return result
}

// Jupyter returns the Jupyter-specific metadata.
func (m CellMetadata) Jupyter() JupyterCellMetadata { return m.jupyter }

// Custom returns a copy of custom metadata fields.
func (m CellMetadata) Custom() map[string]any {
	if len(m.custom) == 0 {
		return nil
	}
	result := make(map[string]any, len(m.custom))
	for k, v := range m.custom {
		result[k] = v
	}
	return result
}

// WithCollapsed returns a new CellMetadata with the collapsed field set.
func (m CellMetadata) WithCollapsed(collapsed bool) CellMetadata {
	m.collapsed = collapsed
	return m
}

// WithScrolled returns a new CellMetadata with the scrolled field set.
func (m CellMetadata) WithScrolled(scrolled ScrolledState) CellMetadata {
	m.scrolled = scrolled
	return m
}

// WithDeletable returns a new CellMetadata with the deletable field set.
func (m CellMetadata) WithDeletable(deletable bool) CellMetadata {
	m.deletable = &deletable
	return m
}

// WithEditable returns a new CellMetadata with the editable field set.
func (m CellMetadata) WithEditable(editable bool) CellMetadata {
	m.editable = &editable
	return m
}

// WithName returns a new CellMetadata with the name field set.
func (m CellMetadata) WithName(name string) CellMetadata {
	m.name = name
	return m
}

// WithTags returns a new CellMetadata with the tags field set.
func (m CellMetadata) WithTags(tags []string) CellMetadata {
	if len(tags) == 0 {
		m.tags = nil
	} else {
		m.tags = make([]string, len(tags))
		copy(m.tags, tags)
	}
	return m
}

// WithJupyter returns a new CellMetadata with the Jupyter metadata set.
func (m CellMetadata) WithJupyter(jupyter JupyterCellMetadata) CellMetadata {
	m.jupyter = jupyter
	return m
}

// WithCustom returns a new CellMetadata with a custom field set.
func (m CellMetadata) WithCustom(key string, value any) CellMetadata {
	if m.custom == nil {
		m.custom = make(map[string]any)
	} else {
		newCustom := make(map[string]any, len(m.custom)+1)
		for k, v := range m.custom {
			newCustom[k] = v
		}
		m.custom = newCustom
	}
	m.custom[key] = value
	return m
}

// SourceHidden returns whether the source is hidden.
func (j JupyterCellMetadata) SourceHidden() bool { return j.sourceHidden }

// OutputsHidden returns whether the outputs are hidden.
func (j JupyterCellMetadata) OutputsHidden() bool { return j.outputsHidden }

// OutputsExceeds returns whether the outputs exceed the limit.
func (j JupyterCellMetadata) OutputsExceeds() bool { return j.outputsExceeds }

// WithSourceHidden returns a new JupyterCellMetadata with the sourceHidden field set.
func (j JupyterCellMetadata) WithSourceHidden(hidden bool) JupyterCellMetadata {
	j.sourceHidden = hidden
	return j
}

// WithOutputsHidden returns a new JupyterCellMetadata with the outputsHidden field set.
func (j JupyterCellMetadata) WithOutputsHidden(hidden bool) JupyterCellMetadata {
	j.outputsHidden = hidden
	return j
}

// WithOutputsExceeds returns a new JupyterCellMetadata with the outputsExceeds field set.
func (j JupyterCellMetadata) WithOutputsExceeds(exceeds bool) JupyterCellMetadata {
	j.outputsExceeds = exceeds
	return j
}

// CodeCell represents an executable code cell.
type CodeCell struct {
	id             string
	source         string
	metadata       CellMetadata
	executionCount *int
	outputs        []Output
}

func (CodeCell) isCell()              {}
func (CodeCell) CellType() CellType   { return CellTypeCode }
func (c CodeCell) Source() string     { return c.source }
func (c CodeCell) Metadata() CellMetadata { return c.metadata }
func (c CodeCell) ID() string         { return c.id }

// ExecutionCount returns the execution count of the cell.
// Returns nil if the cell has not been executed.
func (c CodeCell) ExecutionCount() *int {
	if c.executionCount == nil {
		return nil
	}
	v := *c.executionCount
	return &v
}

// Outputs returns a copy of the cell's outputs.
func (c CodeCell) Outputs() []Output {
	if len(c.outputs) == 0 {
		return nil
	}
	result := make([]Output, len(c.outputs))
	copy(result, c.outputs)
	return result
}

// NewCodeCell creates a new code cell with the given source.
func NewCodeCell(source string) CodeCell {
	return CodeCell{source: source}
}

// WithID returns a new CodeCell with the ID set.
func (c CodeCell) WithID(id string) CodeCell {
	c.id = id
	return c
}

// WithSource returns a new CodeCell with the source set.
func (c CodeCell) WithSource(source string) CodeCell {
	c.source = source
	return c
}

// WithMetadata returns a new CodeCell with the metadata set.
func (c CodeCell) WithMetadata(metadata CellMetadata) CodeCell {
	c.metadata = metadata
	return c
}

// WithExecutionCount returns a new CodeCell with the execution count set.
func (c CodeCell) WithExecutionCount(count int) CodeCell {
	c.executionCount = &count
	return c
}

// WithOutputs returns a new CodeCell with the outputs set.
func (c CodeCell) WithOutputs(outputs []Output) CodeCell {
	if len(outputs) == 0 {
		c.outputs = nil
	} else {
		c.outputs = make([]Output, len(outputs))
		copy(c.outputs, outputs)
	}
	return c
}

// AddOutput returns a new CodeCell with the output appended.
func (c CodeCell) AddOutput(output Output) CodeCell {
	newOutputs := make([]Output, len(c.outputs)+1)
	copy(newOutputs, c.outputs)
	newOutputs[len(c.outputs)] = output
	c.outputs = newOutputs
	return c
}

// MarkdownCell represents a markdown text cell.
type MarkdownCell struct {
	id          string
	source      string
	metadata    CellMetadata
	attachments map[string]MimeBundle
}

func (MarkdownCell) isCell()              {}
func (MarkdownCell) CellType() CellType   { return CellTypeMarkdown }
func (c MarkdownCell) Source() string     { return c.source }
func (c MarkdownCell) Metadata() CellMetadata { return c.metadata }
func (c MarkdownCell) ID() string         { return c.id }

// Attachments returns a copy of the cell's attachments.
func (c MarkdownCell) Attachments() map[string]MimeBundle {
	if len(c.attachments) == 0 {
		return nil
	}
	result := make(map[string]MimeBundle, len(c.attachments))
	for k, v := range c.attachments {
		result[k] = v.clone()
	}
	return result
}

// NewMarkdownCell creates a new markdown cell with the given source.
func NewMarkdownCell(source string) MarkdownCell {
	return MarkdownCell{source: source}
}

// WithID returns a new MarkdownCell with the ID set.
func (c MarkdownCell) WithID(id string) MarkdownCell {
	c.id = id
	return c
}

// WithSource returns a new MarkdownCell with the source set.
func (c MarkdownCell) WithSource(source string) MarkdownCell {
	c.source = source
	return c
}

// WithMetadata returns a new MarkdownCell with the metadata set.
func (c MarkdownCell) WithMetadata(metadata CellMetadata) MarkdownCell {
	c.metadata = metadata
	return c
}

// WithAttachments returns a new MarkdownCell with the attachments set.
func (c MarkdownCell) WithAttachments(attachments map[string]MimeBundle) MarkdownCell {
	if len(attachments) == 0 {
		c.attachments = nil
	} else {
		c.attachments = make(map[string]MimeBundle, len(attachments))
		for k, v := range attachments {
			c.attachments[k] = v.clone()
		}
	}
	return c
}

// RawCell represents a raw, unrendered cell.
type RawCell struct {
	id          string
	source      string
	metadata    CellMetadata
	attachments map[string]MimeBundle
}

func (RawCell) isCell()              {}
func (RawCell) CellType() CellType   { return CellTypeRaw }
func (c RawCell) Source() string     { return c.source }
func (c RawCell) Metadata() CellMetadata { return c.metadata }
func (c RawCell) ID() string         { return c.id }

// Attachments returns a copy of the cell's attachments.
func (c RawCell) Attachments() map[string]MimeBundle {
	if len(c.attachments) == 0 {
		return nil
	}
	result := make(map[string]MimeBundle, len(c.attachments))
	for k, v := range c.attachments {
		result[k] = v.clone()
	}
	return result
}

// NewRawCell creates a new raw cell with the given source.
func NewRawCell(source string) RawCell {
	return RawCell{source: source}
}

// WithID returns a new RawCell with the ID set.
func (c RawCell) WithID(id string) RawCell {
	c.id = id
	return c
}

// WithSource returns a new RawCell with the source set.
func (c RawCell) WithSource(source string) RawCell {
	c.source = source
	return c
}

// WithMetadata returns a new RawCell with the metadata set.
func (c RawCell) WithMetadata(metadata CellMetadata) RawCell {
	c.metadata = metadata
	return c
}

// WithAttachments returns a new RawCell with the attachments set.
func (c RawCell) WithAttachments(attachments map[string]MimeBundle) RawCell {
	if len(attachments) == 0 {
		c.attachments = nil
	} else {
		c.attachments = make(map[string]MimeBundle, len(attachments))
		for k, v := range attachments {
			c.attachments[k] = v.clone()
		}
	}
	return c
}

// MimeBundle represents a collection of data in various MIME types.
type MimeBundle struct {
	data map[string]any
}

// NewMimeBundle creates a new empty MimeBundle.
func NewMimeBundle() MimeBundle {
	return MimeBundle{}
}

// Data returns a copy of the MIME data.
func (m MimeBundle) Data() map[string]any {
	if len(m.data) == 0 {
		return nil
	}
	result := make(map[string]any, len(m.data))
	for k, v := range m.data {
		result[k] = v
	}
	return result
}

// Get returns the data for the given MIME type.
func (m MimeBundle) Get(mimeType string) (any, bool) {
	v, ok := m.data[mimeType]
	return v, ok
}

// WithData returns a new MimeBundle with the data for the given MIME type set.
func (m MimeBundle) WithData(mimeType string, data any) MimeBundle {
	if m.data == nil {
		m.data = make(map[string]any)
	} else {
		newData := make(map[string]any, len(m.data)+1)
		for k, v := range m.data {
			newData[k] = v
		}
		m.data = newData
	}
	m.data[mimeType] = data
	return m
}

func (m MimeBundle) clone() MimeBundle {
	if len(m.data) == 0 {
		return MimeBundle{}
	}
	newData := make(map[string]any, len(m.data))
	for k, v := range m.data {
		newData[k] = v
	}
	return MimeBundle{data: newData}
}
