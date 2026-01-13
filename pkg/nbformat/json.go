package nbformat

import (
	"fmt"
	"io"
	"os"

	"github.com/finos/morphir/pkg/nbformat/internal/json"
)

// ReadOptions configures notebook reading.
type ReadOptions struct {
	// StrictValidation enables strict schema validation during reading.
	StrictValidation bool
}

// WriteOptions configures notebook writing.
type WriteOptions struct {
	// Indent is the indentation string. Default is single space.
	Indent string
}

// DefaultWriteOptions returns the default write options.
func DefaultWriteOptions() WriteOptions {
	return WriteOptions{
		Indent: " ",
	}
}

// ReadFile reads a notebook from a file.
func ReadFile(path string) (Notebook, error) {
	f, err := os.Open(path)
	if err != nil {
		return Notebook{}, fmt.Errorf("failed to open notebook file: %w", err)
	}
	defer func() { _ = f.Close() }()
	return Read(f)
}

// Read reads a notebook from a reader.
func Read(r io.Reader) (Notebook, error) {
	nbJSON, err := json.DecodeNotebookFromReader(r)
	if err != nil {
		return Notebook{}, err
	}
	return fromJSON(nbJSON), nil
}

// ReadBytes reads a notebook from bytes.
func ReadBytes(data []byte) (Notebook, error) {
	nbJSON, err := json.DecodeNotebook(data)
	if err != nil {
		return Notebook{}, err
	}
	return fromJSON(nbJSON), nil
}

// WriteFile writes a notebook to a file.
func WriteFile(nb Notebook, path string) error {
	return WriteFileWithOptions(nb, path, DefaultWriteOptions())
}

// WriteFileWithOptions writes a notebook to a file with options.
func WriteFileWithOptions(nb Notebook, path string, opts WriteOptions) error {
	f, err := os.Create(path)
	if err != nil {
		return fmt.Errorf("failed to create notebook file: %w", err)
	}
	defer func() { _ = f.Close() }()
	return WriteWithOptions(nb, f, opts)
}

// Write writes a notebook to a writer.
func Write(nb Notebook, w io.Writer) error {
	return WriteWithOptions(nb, w, DefaultWriteOptions())
}

// WriteWithOptions writes a notebook to a writer with options.
func WriteWithOptions(nb Notebook, w io.Writer, opts WriteOptions) error {
	nbJSON := toJSON(nb)
	encOpts := json.EncodeOptions{
		Indent:          opts.Indent,
		TrailingNewline: true,
	}
	return json.EncodeNotebookToWriter(nbJSON, w, encOpts)
}

// WriteBytes writes a notebook to bytes.
func WriteBytes(nb Notebook) ([]byte, error) {
	return WriteBytesWithOptions(nb, DefaultWriteOptions())
}

// WriteBytesWithOptions writes a notebook to bytes with options.
func WriteBytesWithOptions(nb Notebook, opts WriteOptions) ([]byte, error) {
	nbJSON := toJSON(nb)
	encOpts := json.EncodeOptions{
		Indent:          opts.Indent,
		TrailingNewline: true,
	}
	return json.EncodeNotebook(nbJSON, encOpts)
}

// fromJSON converts a JSON notebook to a domain Notebook.
func fromJSON(nbJSON *json.NotebookJSON) Notebook {
	nb := NewNotebookWithVersion(nbJSON.NBFormat, nbJSON.NBFormatMinor)
	nb = nb.WithMetadata(metadataFromJSON(nbJSON.Metadata))

	cells := make([]Cell, 0, len(nbJSON.Cells))
	for _, cellJSON := range nbJSON.Cells {
		cells = append(cells, cellFromJSON(cellJSON))
	}
	return nb.WithCells(cells)
}

// metadataFromJSON converts JSON metadata to domain NotebookMetadata.
func metadataFromJSON(m json.NotebookMetadataJSON) NotebookMetadata {
	meta := NewNotebookMetadata().WithTitle(m.Title)

	if m.KernelSpec != nil {
		ks := NewKernelSpec(m.KernelSpec.Name, m.KernelSpec.DisplayName).
			WithLanguage(m.KernelSpec.Language)
		meta = meta.WithKernelSpec(ks)
	}

	if m.LanguageInfo != nil {
		li := NewLanguageInfo(m.LanguageInfo.Name).
			WithVersion(m.LanguageInfo.Version).
			WithMimeType(m.LanguageInfo.MimeType).
			WithFileExtension(m.LanguageInfo.FileExtension).
			WithPygmentsLexer(m.LanguageInfo.PygmentsLexer).
			WithCodemirrorMode(m.LanguageInfo.CodemirrorMode).
			WithNBConvertExporter(m.LanguageInfo.NBConvertExporter)
		meta = meta.WithLanguageInfo(li)
	}

	if len(m.Authors) > 0 {
		authors := make([]Author, 0, len(m.Authors))
		for _, a := range m.Authors {
			authors = append(authors, NewAuthor(a.Name))
		}
		meta = meta.WithAuthors(authors)
	}

	return meta
}

// cellFromJSON converts a JSON cell to a domain Cell.
func cellFromJSON(c json.CellJSON) Cell {
	cellMeta := cellMetadataFromJSON(c.Metadata)

	switch c.CellType {
	case "code":
		cell := NewCodeCell(c.Source.String()).
			WithID(c.ID).
			WithMetadata(cellMeta)
		if c.ExecutionCount != nil {
			cell = cell.WithExecutionCount(*c.ExecutionCount)
		}
		outputs := make([]Output, 0, len(c.Outputs))
		for _, o := range c.Outputs {
			outputs = append(outputs, outputFromJSON(o))
		}
		return cell.WithOutputs(outputs)

	case "markdown":
		cell := NewMarkdownCell(c.Source.String()).
			WithID(c.ID).
			WithMetadata(cellMeta)
		if c.Attachments != nil {
			attachments := make(map[string]MimeBundle, len(c.Attachments))
			for name, data := range c.Attachments {
				if m, ok := data.(map[string]any); ok {
					attachments[name] = mimeBundleFromJSON(m)
				}
			}
			cell = cell.WithAttachments(attachments)
		}
		return cell

	case "raw":
		cell := NewRawCell(c.Source.String()).
			WithID(c.ID).
			WithMetadata(cellMeta)
		if c.Attachments != nil {
			attachments := make(map[string]MimeBundle, len(c.Attachments))
			for name, data := range c.Attachments {
				if m, ok := data.(map[string]any); ok {
					attachments[name] = mimeBundleFromJSON(m)
				}
			}
			cell = cell.WithAttachments(attachments)
		}
		return cell

	default:
		// Unknown cell type - treat as raw
		return NewRawCell(c.Source.String()).WithID(c.ID).WithMetadata(cellMeta)
	}
}

// cellMetadataFromJSON converts JSON cell metadata to domain CellMetadata.
func cellMetadataFromJSON(m json.CellMetadataJSON) CellMetadata {
	meta := NewCellMetadata().
		WithCollapsed(m.Collapsed).
		WithName(m.Name)

	scrolled := json.ParseScrolled(m.Scrolled)
	meta = meta.WithScrolled(ScrolledState(scrolled))

	if m.Deletable != nil {
		meta = meta.WithDeletable(*m.Deletable)
	}
	if m.Editable != nil {
		meta = meta.WithEditable(*m.Editable)
	}
	if len(m.Tags) > 0 {
		meta = meta.WithTags(m.Tags)
	}
	if m.Jupyter != nil {
		jupyter := JupyterCellMetadata{}.
			WithSourceHidden(m.Jupyter.SourceHidden).
			WithOutputsHidden(m.Jupyter.OutputsHidden)
		meta = meta.WithJupyter(jupyter)
	}

	return meta
}

// outputFromJSON converts a JSON output to a domain Output.
func outputFromJSON(o json.OutputJSON) Output {
	switch o.OutputType {
	case "stream":
		name := StreamStdout
		if o.Name == "stderr" {
			name = StreamStderr
		}
		return NewStreamOutput(name, o.Text.String())

	case "display_data":
		data := mimeBundleFromJSON(json.ParseMimeBundle(o.Data))
		output := NewDisplayDataOutput(data)
		if o.Metadata != nil {
			output = output.WithMetadata(mimeBundleFromJSON(o.Metadata))
		}
		return output

	case "execute_result":
		count := 0
		if o.ExecutionCount != nil {
			count = *o.ExecutionCount
		}
		data := mimeBundleFromJSON(json.ParseMimeBundle(o.Data))
		output := NewExecuteResultOutput(count, data)
		if o.Metadata != nil {
			output = output.WithMetadata(mimeBundleFromJSON(o.Metadata))
		}
		return output

	case "error":
		return NewErrorOutput(o.Ename, o.Evalue, o.Traceback)

	default:
		// Unknown output type - return as error
		return NewErrorOutput("UnknownOutputType", o.OutputType, nil)
	}
}

// mimeBundleFromJSON converts a map to a MimeBundle.
func mimeBundleFromJSON(data map[string]any) MimeBundle {
	bundle := NewMimeBundle()
	for k, v := range data {
		bundle = bundle.WithData(k, v)
	}
	return bundle
}

// toJSON converts a domain Notebook to a JSON notebook.
func toJSON(nb Notebook) *json.NotebookJSON {
	cells := make([]json.CellJSON, 0, nb.CellCount())
	for i := 0; i < nb.CellCount(); i++ {
		cells = append(cells, cellToJSON(nb.Cell(i)))
	}

	return &json.NotebookJSON{
		NBFormat:      nb.NBFormat(),
		NBFormatMinor: nb.NBFormatMinor(),
		Metadata:      metadataToJSON(nb.Metadata()),
		Cells:         cells,
	}
}

// metadataToJSON converts domain NotebookMetadata to JSON.
func metadataToJSON(m NotebookMetadata) json.NotebookMetadataJSON {
	meta := json.NotebookMetadataJSON{
		Title: m.Title(),
	}

	if ks := m.KernelSpec(); ks != nil {
		meta.KernelSpec = &json.KernelSpecJSON{
			Name:        ks.Name(),
			DisplayName: ks.DisplayName(),
			Language:    ks.Language(),
		}
	}

	if li := m.LanguageInfo(); li != nil {
		meta.LanguageInfo = &json.LanguageInfoJSON{
			Name:              li.Name(),
			Version:           li.Version(),
			MimeType:          li.MimeType(),
			FileExtension:     li.FileExtension(),
			PygmentsLexer:     li.PygmentsLexer(),
			CodemirrorMode:    li.CodemirrorMode(),
			NBConvertExporter: li.NBConvertExporter(),
		}
	}

	if authors := m.Authors(); len(authors) > 0 {
		meta.Authors = make([]json.AuthorJSON, 0, len(authors))
		for _, a := range authors {
			meta.Authors = append(meta.Authors, json.AuthorJSON{Name: a.Name()})
		}
	}

	return meta
}

// cellToJSON converts a domain Cell to JSON.
func cellToJSON(cell Cell) json.CellJSON {
	cellJSON := json.CellJSON{
		ID:       cell.ID(),
		CellType: string(cell.CellType()),
		Source:   json.MultilineString(cell.Source()),
		Metadata: cellMetadataToJSON(cell.Metadata()),
	}

	switch c := cell.(type) {
	case CodeCell:
		if ec := c.ExecutionCount(); ec != nil {
			cellJSON.ExecutionCount = ec
		}
		outputs := c.Outputs()
		if len(outputs) > 0 {
			cellJSON.Outputs = make([]json.OutputJSON, 0, len(outputs))
			for _, o := range outputs {
				cellJSON.Outputs = append(cellJSON.Outputs, outputToJSON(o))
			}
		}

	case MarkdownCell:
		if att := c.Attachments(); len(att) > 0 {
			cellJSON.Attachments = make(map[string]any, len(att))
			for name, bundle := range att {
				cellJSON.Attachments[name] = mimeBundleToJSON(bundle)
			}
		}

	case RawCell:
		if att := c.Attachments(); len(att) > 0 {
			cellJSON.Attachments = make(map[string]any, len(att))
			for name, bundle := range att {
				cellJSON.Attachments[name] = mimeBundleToJSON(bundle)
			}
		}
	}

	return cellJSON
}

// cellMetadataToJSON converts domain CellMetadata to JSON.
func cellMetadataToJSON(m CellMetadata) json.CellMetadataJSON {
	meta := json.CellMetadataJSON{
		Collapsed: m.Collapsed(),
		Name:      m.Name(),
		Tags:      m.Tags(),
	}

	meta.Scrolled = json.FormatScrolled(int(m.Scrolled()))
	meta.Deletable = m.Deletable()
	meta.Editable = m.Editable()

	jupyter := m.Jupyter()
	if jupyter.SourceHidden() || jupyter.OutputsHidden() {
		meta.Jupyter = &json.JupyterCellMetaJSON{
			SourceHidden:  jupyter.SourceHidden(),
			OutputsHidden: jupyter.OutputsHidden(),
		}
	}

	return meta
}

// outputToJSON converts a domain Output to JSON.
func outputToJSON(output Output) json.OutputJSON {
	switch o := output.(type) {
	case StreamOutput:
		return json.OutputJSON{
			OutputType: "stream",
			Name:       string(o.Name()),
			Text:       json.MultilineString(o.Text()),
		}

	case DisplayDataOutput:
		return json.OutputJSON{
			OutputType: "display_data",
			Data:       json.FormatMimeBundle(mimeBundleToJSON(o.Data())),
			Metadata:   mimeBundleToJSON(o.Metadata()),
		}

	case ExecuteResultOutput:
		ec := o.ExecutionCount()
		return json.OutputJSON{
			OutputType:     "execute_result",
			ExecutionCount: &ec,
			Data:           json.FormatMimeBundle(mimeBundleToJSON(o.Data())),
			Metadata:       mimeBundleToJSON(o.Metadata()),
		}

	case ErrorOutput:
		return json.OutputJSON{
			OutputType: "error",
			Ename:      o.Ename(),
			Evalue:     o.Evalue(),
			Traceback:  o.Traceback(),
		}

	default:
		return json.OutputJSON{OutputType: "error"}
	}
}

// mimeBundleToJSON converts a MimeBundle to a map.
func mimeBundleToJSON(bundle MimeBundle) map[string]any {
	return bundle.Data()
}
