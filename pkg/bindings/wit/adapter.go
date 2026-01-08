package wit

import (
	"github.com/finos/morphir/pkg/bindings/wit/domain"
	"github.com/finos/morphir/pkg/bindings/wit/internal/adapter"
	"go.bytecodealliance.org/wit"
)

// ParseWIT converts a wit.Resolve to domain.Package slice.
// This is the main entry point for converting WIT packages to the Morphir domain model.
//
// Returns:
//   - []domain.Package: The converted packages
//   - []string: Warning messages (non-fatal issues during conversion)
//   - error: Fatal error if conversion failed
func ParseWIT(resolve *wit.Resolve) ([]domain.Package, []string, error) {
	return adapter.FromWIT(resolve)
}

// LoadAndParseWIT loads a WIT file and converts it to domain.Package slice.
// This is a convenience function that combines wit.LoadWIT and ParseWIT.
//
// Parameters:
//   - path: Path to the WIT file to load
//
// Returns:
//   - []domain.Package: The converted packages
//   - []string: Warning messages (non-fatal issues during conversion)
//   - error: Fatal error if loading or conversion failed
func LoadAndParseWIT(path string) ([]domain.Package, []string, error) {
	resolve, err := wit.LoadWIT(path)
	if err != nil {
		return nil, nil, err
	}
	return ParseWIT(resolve)
}
