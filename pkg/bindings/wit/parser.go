package wit

import (
	"os"

	"github.com/finos/morphir/pkg/bindings/wit/domain"
	"github.com/finos/morphir/pkg/bindings/wit/internal/parser"
)

// ParseWITSource parses WIT source code using the pure Go parser.
// This parser does not depend on external WebAssembly components.
//
// Example:
//
//	pkg, err := wit.ParseWITSource(`
//	    package example:calculator@1.0.0;
//
//	    interface ops {
//	        add: func(a: u32, b: u32) -> u32;
//	    }
//	`)
func ParseWITSource(source string) (domain.Package, error) {
	p := parser.NewParser(source)
	return p.Parse()
}

// ParseWITFile parses a WIT file using the pure Go parser.
// This is a convenience function that reads the file and calls ParseWITSource.
//
// Example:
//
//	pkg, err := wit.ParseWITFile("path/to/file.wit")
func ParseWITFile(path string) (domain.Package, error) {
	content, err := os.ReadFile(path)
	if err != nil {
		return domain.Package{}, err
	}
	return ParseWITSource(string(content))
}
