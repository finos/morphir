package domain

// GoModule represents a Go module with its packages and metadata.
// A module corresponds to a directory with a go.mod file.
type GoModule struct {
	// ModulePath is the Go module path (e.g., "github.com/example/myapp")
	ModulePath string

	// GoVersion is the minimum Go version required (e.g., "1.25")
	GoVersion string

	// Packages contains all Go packages in this module
	Packages []GoPackage

	// Dependencies maps module paths to version constraints
	Dependencies map[string]string
}

// GoPackage represents a Go package with its types and functions.
// A package corresponds to a directory with .go files.
type GoPackage struct {
	// Name is the package name (last component of import path)
	Name string

	// ImportPath is the full import path (e.g., "github.com/example/myapp/pkg/models")
	ImportPath string

	// Documentation is the package-level documentation
	Documentation string

	// Types contains all type definitions in this package
	Types []GoType

	// Functions contains all function definitions in this package
	Functions []GoFunction

	// Imports contains all import statements needed by this package
	Imports []GoImport
}

// GoImport represents an import statement.
type GoImport struct {
	// Path is the import path (e.g., "fmt", "github.com/example/pkg")
	Path string

	// Alias is the optional import alias (e.g., "." for dot imports)
	Alias string
}

// GoType is a sealed interface for Go type definitions.
// Use type switch to handle specific type variants.
type GoType interface {
	TypeName() string
	isGoType()
}

// GoStructType represents a Go struct definition.
type GoStructType struct {
	Name          string
	Documentation string
	Fields        []GoField
	Methods       []GoMethod
}

func (GoStructType) isGoType()          {}
func (g GoStructType) TypeName() string { return g.Name }

// GoInterfaceType represents a Go interface definition.
type GoInterfaceType struct {
	Name          string
	Documentation string
	Methods       []GoMethodSignature
}

func (GoInterfaceType) isGoType()          {}
func (g GoInterfaceType) TypeName() string { return g.Name }

// GoTypeAliasType represents a Go type alias (type T = U).
type GoTypeAliasType struct {
	Name           string
	Documentation  string
	UnderlyingType string
}

func (GoTypeAliasType) isGoType()          {}
func (g GoTypeAliasType) TypeName() string { return g.Name }

// GoField represents a struct field.
type GoField struct {
	Name          string
	Type          string
	Tag           string // struct tag (e.g., `json:"name"`)
	Documentation string
}

// GoMethod represents a method on a type.
type GoMethod struct {
	Receiver  GoReceiver
	Signature GoMethodSignature
	Body      string // method body as Go code
}

// GoMethodSignature represents a method signature.
type GoMethodSignature struct {
	Name          string
	Parameters    []GoParameter
	Results       []GoParameter
	Documentation string
}

// GoReceiver represents a method receiver.
type GoReceiver struct {
	Name      string
	Type      string
	IsPointer bool
}

// GoParameter represents a function/method parameter or result.
type GoParameter struct {
	Name string
	Type string
}

// GoFunction represents a top-level function.
type GoFunction struct {
	Name          string
	Parameters    []GoParameter
	Results       []GoParameter
	Body          string // function body as Go code
	Documentation string
}

// GoWorkspace represents a multi-module Go workspace.
type GoWorkspace struct {
	// Modules contains all modules in the workspace
	Modules []GoModule

	// GoVersion is the minimum Go version for the workspace
	GoVersion string
}
