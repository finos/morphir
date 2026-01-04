package steps

import (
	"context"
	"encoding/json"
	"fmt"
	"io/fs"

	ir "github.com/finos/morphir/pkg/models/ir"
	codec "github.com/finos/morphir/pkg/models/ir/codec/json"
)

// testContextKey is used to store TestContext in context.Context.
type testContextKey struct{}

// TestContext holds state for BDD test scenarios.
type TestContext struct {
	// Fixtures is the embedded filesystem containing test fixtures.
	Fixtures fs.FS

	// CurrentFixturePath is the path to the currently loaded fixture.
	CurrentFixturePath string

	// CurrentJSON is the raw JSON data from the current fixture.
	CurrentJSON json.RawMessage

	// FormatVersion is the format version being used for encoding/decoding.
	FormatVersion codec.FormatVersion

	// DecodedDistribution is the decoded distribution (if applicable).
	DecodedDistribution ir.Distribution

	// DecodedType is the decoded type (if applicable).
	DecodedType ir.Type[ir.Unit]

	// LastError holds the last error encountered during operations.
	LastError error

	// EncodedJSON holds the result of encoding operations.
	EncodedJSON json.RawMessage
}

// NewTestContext creates a new test context with the given fixtures filesystem.
func NewTestContext(fixtures fs.FS) *TestContext {
	return &TestContext{
		Fixtures:      fixtures,
		FormatVersion: codec.FormatV3, // Default to V3
	}
}

// WithTestContext returns a new context.Context with the TestContext attached.
func WithTestContext(ctx context.Context, tc *TestContext) context.Context {
	return context.WithValue(ctx, testContextKey{}, tc)
}

// GetTestContext retrieves the TestContext from the context.Context.
func GetTestContext(ctx context.Context) (*TestContext, error) {
	tc, ok := ctx.Value(testContextKey{}).(*TestContext)
	if !ok {
		return nil, fmt.Errorf("test context not found in context")
	}
	return tc, nil
}

// LoadFixture loads a JSON fixture from the embedded filesystem.
func (tc *TestContext) LoadFixture(path string) error {
	data, err := fs.ReadFile(tc.Fixtures, path)
	if err != nil {
		return fmt.Errorf("failed to load fixture %q: %w", path, err)
	}
	tc.CurrentFixturePath = path
	tc.CurrentJSON = data
	tc.LastError = nil
	return nil
}

// SetFormatVersion sets the format version for encoding/decoding.
func (tc *TestContext) SetFormatVersion(version int) error {
	switch version {
	case 1:
		tc.FormatVersion = codec.FormatV1
	case 2:
		tc.FormatVersion = codec.FormatV2
	case 3:
		tc.FormatVersion = codec.FormatV3
	default:
		return fmt.Errorf("unsupported format version: %d", version)
	}
	return nil
}

// DecodeDistribution decodes the current JSON as a Distribution.
func (tc *TestContext) DecodeDistribution() error {
	opts := codec.Options{FormatVersion: tc.FormatVersion}
	dist, err := codec.DecodeDistribution(opts, tc.CurrentJSON)
	if err != nil {
		tc.LastError = err
		return nil // Don't return error - store it for assertion
	}
	tc.DecodedDistribution = dist
	tc.LastError = nil
	return nil
}

// EncodeDistribution encodes the decoded distribution back to JSON.
func (tc *TestContext) EncodeDistribution() error {
	if tc.DecodedDistribution == nil {
		return fmt.Errorf("no distribution to encode")
	}
	opts := codec.Options{FormatVersion: tc.FormatVersion}
	data, err := codec.EncodeDistribution(opts, tc.DecodedDistribution)
	if err != nil {
		tc.LastError = err
		return nil
	}
	tc.EncodedJSON = data
	tc.LastError = nil
	return nil
}

// DecodeType decodes the current JSON as a Type.
func (tc *TestContext) DecodeType() error {
	opts := codec.Options{FormatVersion: tc.FormatVersion}
	decodeUnit := func(raw json.RawMessage) (ir.Unit, error) {
		return ir.Unit{}, nil
	}
	typ, err := codec.DecodeType(opts, decodeUnit, tc.CurrentJSON)
	if err != nil {
		tc.LastError = err
		return nil
	}
	tc.DecodedType = typ
	tc.LastError = nil
	return nil
}

// Reset clears the test context state for a new scenario.
func (tc *TestContext) Reset() {
	tc.CurrentFixturePath = ""
	tc.CurrentJSON = nil
	tc.FormatVersion = codec.FormatV3
	tc.DecodedDistribution = nil
	tc.DecodedType = nil
	tc.LastError = nil
	tc.EncodedJSON = nil
}
