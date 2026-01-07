package nbformat

// NBFormat is the major version of the notebook format.
const NBFormat = 4

// NBFormatMinor is the minor version of the notebook format supported by this package.
const NBFormatMinor = 5

// Notebook represents a Jupyter notebook document.
type Notebook struct {
	nbformat      int
	nbformatMinor int
	metadata      NotebookMetadata
	cells         []Cell
}

// NBFormat returns the major version number of the notebook format.
func (n Notebook) NBFormat() int { return n.nbformat }

// NBFormatMinor returns the minor version number of the notebook format.
func (n Notebook) NBFormatMinor() int { return n.nbformatMinor }

// Metadata returns the notebook's metadata.
func (n Notebook) Metadata() NotebookMetadata { return n.metadata }

// Cells returns a copy of the notebook's cells.
func (n Notebook) Cells() []Cell {
	if len(n.cells) == 0 {
		return nil
	}
	result := make([]Cell, len(n.cells))
	copy(result, n.cells)
	return result
}

// CellCount returns the number of cells in the notebook.
func (n Notebook) CellCount() int { return len(n.cells) }

// Cell returns the cell at the given index.
// Panics if the index is out of bounds.
func (n Notebook) Cell(index int) Cell { return n.cells[index] }

// NewNotebook creates a new empty notebook with the current format version.
func NewNotebook() Notebook {
	return Notebook{
		nbformat:      NBFormat,
		nbformatMinor: NBFormatMinor,
	}
}

// NewNotebookWithVersion creates a new empty notebook with the specified format version.
func NewNotebookWithVersion(nbformat, nbformatMinor int) Notebook {
	return Notebook{
		nbformat:      nbformat,
		nbformatMinor: nbformatMinor,
	}
}

// WithMetadata returns a new Notebook with the metadata set.
func (n Notebook) WithMetadata(metadata NotebookMetadata) Notebook {
	n.metadata = metadata
	return n
}

// WithCells returns a new Notebook with the cells set.
func (n Notebook) WithCells(cells []Cell) Notebook {
	if len(cells) == 0 {
		n.cells = nil
	} else {
		n.cells = make([]Cell, len(cells))
		copy(n.cells, cells)
	}
	return n
}

// AddCell returns a new Notebook with the cell appended.
func (n Notebook) AddCell(cell Cell) Notebook {
	newCells := make([]Cell, len(n.cells)+1)
	copy(newCells, n.cells)
	newCells[len(n.cells)] = cell
	n.cells = newCells
	return n
}

// InsertCell returns a new Notebook with the cell inserted at the given index.
// If index is out of bounds, the cell is appended.
func (n Notebook) InsertCell(index int, cell Cell) Notebook {
	if index >= len(n.cells) {
		return n.AddCell(cell)
	}
	if index < 0 {
		index = 0
	}
	newCells := make([]Cell, len(n.cells)+1)
	copy(newCells[:index], n.cells[:index])
	newCells[index] = cell
	copy(newCells[index+1:], n.cells[index:])
	n.cells = newCells
	return n
}

// RemoveCell returns a new Notebook with the cell at the given index removed.
// If index is out of bounds, returns the notebook unchanged.
func (n Notebook) RemoveCell(index int) Notebook {
	if index < 0 || index >= len(n.cells) {
		return n
	}
	newCells := make([]Cell, len(n.cells)-1)
	copy(newCells[:index], n.cells[:index])
	copy(newCells[index:], n.cells[index+1:])
	n.cells = newCells
	return n
}

// ReplaceCell returns a new Notebook with the cell at the given index replaced.
// If index is out of bounds, returns the notebook unchanged.
func (n Notebook) ReplaceCell(index int, cell Cell) Notebook {
	if index < 0 || index >= len(n.cells) {
		return n
	}
	newCells := make([]Cell, len(n.cells))
	copy(newCells, n.cells)
	newCells[index] = cell
	n.cells = newCells
	return n
}

// WithNBFormat returns a new Notebook with the format version set.
func (n Notebook) WithNBFormat(nbformat, nbformatMinor int) Notebook {
	n.nbformat = nbformat
	n.nbformatMinor = nbformatMinor
	return n
}

// NotebookMetadata contains metadata about the notebook.
type NotebookMetadata struct {
	kernelspec   *KernelSpec
	languageInfo *LanguageInfo
	title        string
	authors      []Author
	custom       map[string]any
}

// KernelSpec returns the kernel specification, or nil if not set.
func (m NotebookMetadata) KernelSpec() *KernelSpec {
	if m.kernelspec == nil {
		return nil
	}
	ks := *m.kernelspec
	return &ks
}

// LanguageInfo returns the language information, or nil if not set.
func (m NotebookMetadata) LanguageInfo() *LanguageInfo {
	if m.languageInfo == nil {
		return nil
	}
	li := *m.languageInfo
	return &li
}

// Title returns the notebook title.
func (m NotebookMetadata) Title() string { return m.title }

// Authors returns a copy of the notebook authors.
func (m NotebookMetadata) Authors() []Author {
	if len(m.authors) == 0 {
		return nil
	}
	result := make([]Author, len(m.authors))
	copy(result, m.authors)
	return result
}

// Custom returns a copy of custom metadata fields.
func (m NotebookMetadata) Custom() map[string]any {
	if len(m.custom) == 0 {
		return nil
	}
	result := make(map[string]any, len(m.custom))
	for k, v := range m.custom {
		result[k] = v
	}
	return result
}

// NewNotebookMetadata creates a new empty NotebookMetadata.
func NewNotebookMetadata() NotebookMetadata {
	return NotebookMetadata{}
}

// WithKernelSpec returns a new NotebookMetadata with the kernel spec set.
func (m NotebookMetadata) WithKernelSpec(kernelspec KernelSpec) NotebookMetadata {
	m.kernelspec = &kernelspec
	return m
}

// WithLanguageInfo returns a new NotebookMetadata with the language info set.
func (m NotebookMetadata) WithLanguageInfo(languageInfo LanguageInfo) NotebookMetadata {
	m.languageInfo = &languageInfo
	return m
}

// WithTitle returns a new NotebookMetadata with the title set.
func (m NotebookMetadata) WithTitle(title string) NotebookMetadata {
	m.title = title
	return m
}

// WithAuthors returns a new NotebookMetadata with the authors set.
func (m NotebookMetadata) WithAuthors(authors []Author) NotebookMetadata {
	if len(authors) == 0 {
		m.authors = nil
	} else {
		m.authors = make([]Author, len(authors))
		copy(m.authors, authors)
	}
	return m
}

// WithCustom returns a new NotebookMetadata with a custom field set.
func (m NotebookMetadata) WithCustom(key string, value any) NotebookMetadata {
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

// KernelSpec describes the kernel used to run the notebook.
type KernelSpec struct {
	name        string
	displayName string
	language    string
}

// Name returns the kernel name.
func (k KernelSpec) Name() string { return k.name }

// DisplayName returns the kernel display name.
func (k KernelSpec) DisplayName() string { return k.displayName }

// Language returns the kernel language.
func (k KernelSpec) Language() string { return k.language }

// NewKernelSpec creates a new KernelSpec.
func NewKernelSpec(name, displayName string) KernelSpec {
	return KernelSpec{name: name, displayName: displayName}
}

// WithName returns a new KernelSpec with the name set.
func (k KernelSpec) WithName(name string) KernelSpec {
	k.name = name
	return k
}

// WithDisplayName returns a new KernelSpec with the display name set.
func (k KernelSpec) WithDisplayName(displayName string) KernelSpec {
	k.displayName = displayName
	return k
}

// WithLanguage returns a new KernelSpec with the language set.
func (k KernelSpec) WithLanguage(language string) KernelSpec {
	k.language = language
	return k
}

// LanguageInfo describes the programming language of the notebook.
type LanguageInfo struct {
	name              string
	version           string
	mimeType          string
	fileExtension     string
	pygmentsLexer     string
	codemirrorMode    any
	nbconvertExporter string
}

// Name returns the language name.
func (l LanguageInfo) Name() string { return l.name }

// Version returns the language version.
func (l LanguageInfo) Version() string { return l.version }

// MimeType returns the MIME type for code in this language.
func (l LanguageInfo) MimeType() string { return l.mimeType }

// FileExtension returns the file extension for this language.
func (l LanguageInfo) FileExtension() string { return l.fileExtension }

// PygmentsLexer returns the Pygments lexer name.
func (l LanguageInfo) PygmentsLexer() string { return l.pygmentsLexer }

// CodemirrorMode returns the CodeMirror mode (can be string or object).
func (l LanguageInfo) CodemirrorMode() any { return l.codemirrorMode }

// NBConvertExporter returns the nbconvert exporter name.
func (l LanguageInfo) NBConvertExporter() string { return l.nbconvertExporter }

// NewLanguageInfo creates a new LanguageInfo with the given name.
func NewLanguageInfo(name string) LanguageInfo {
	return LanguageInfo{name: name}
}

// WithName returns a new LanguageInfo with the name set.
func (l LanguageInfo) WithName(name string) LanguageInfo {
	l.name = name
	return l
}

// WithVersion returns a new LanguageInfo with the version set.
func (l LanguageInfo) WithVersion(version string) LanguageInfo {
	l.version = version
	return l
}

// WithMimeType returns a new LanguageInfo with the MIME type set.
func (l LanguageInfo) WithMimeType(mimeType string) LanguageInfo {
	l.mimeType = mimeType
	return l
}

// WithFileExtension returns a new LanguageInfo with the file extension set.
func (l LanguageInfo) WithFileExtension(fileExtension string) LanguageInfo {
	l.fileExtension = fileExtension
	return l
}

// WithPygmentsLexer returns a new LanguageInfo with the Pygments lexer set.
func (l LanguageInfo) WithPygmentsLexer(pygmentsLexer string) LanguageInfo {
	l.pygmentsLexer = pygmentsLexer
	return l
}

// WithCodemirrorMode returns a new LanguageInfo with the CodeMirror mode set.
func (l LanguageInfo) WithCodemirrorMode(codemirrorMode any) LanguageInfo {
	l.codemirrorMode = codemirrorMode
	return l
}

// WithNBConvertExporter returns a new LanguageInfo with the nbconvert exporter set.
func (l LanguageInfo) WithNBConvertExporter(nbconvertExporter string) LanguageInfo {
	l.nbconvertExporter = nbconvertExporter
	return l
}

// Author represents an author of the notebook.
type Author struct {
	name string
}

// Name returns the author's name.
func (a Author) Name() string { return a.name }

// NewAuthor creates a new Author with the given name.
func NewAuthor(name string) Author {
	return Author{name: name}
}

// WithName returns a new Author with the name set.
func (a Author) WithName(name string) Author {
	a.name = name
	return a
}
