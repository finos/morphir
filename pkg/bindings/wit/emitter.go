package wit

import (
	"github.com/finos/morphir/pkg/bindings/wit/domain"
	"github.com/finos/morphir/pkg/bindings/wit/internal/emitter"
)

// EmitPackage converts a domain.Package to WIT text format.
// This is the main entry point for generating WIT from the domain model.
//
// Example:
//
//	pkg := domain.Package{
//	    Namespace: domain.MustNewNamespace("wasi"),
//	    Name:      domain.MustNewPackageName("clocks"),
//	    // ...
//	}
//	witText := wit.EmitPackage(pkg)
func EmitPackage(pkg domain.Package) string {
	return emitter.EmitPackage(pkg)
}
