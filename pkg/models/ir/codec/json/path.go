package json

import (
	"bytes"
	"encoding/json"
	"fmt"

	ir "github.com/finos/morphir-go/pkg/models/ir"
)

// EncodePath encodes a Morphir ir.Path to JSON according to the provided options.
//
// By default (schema-compatible), a Path is encoded as a JSON array of Names.
func EncodePath(opts Options, path ir.Path) ([]byte, error) {
	opts = opts.withDefaults()

	parts := path.Parts()
	rawParts := make([]json.RawMessage, 0, len(parts))
	for _, part := range parts {
		b, err := EncodeName(opts, part)
		if err != nil {
			return nil, err
		}
		rawParts = append(rawParts, json.RawMessage(b))
	}
	return json.Marshal(rawParts)
}

// DecodePath decodes a Morphir ir.Path from JSON according to the provided options.
//
// By default (schema-compatible), a Path is decoded from a JSON array of Names.
func DecodePath(opts Options, data []byte) (ir.Path, error) {
	opts = opts.withDefaults()

	trimmed := bytes.TrimSpace(data)
	if bytes.Equal(trimmed, []byte("null")) {
		return ir.Path{}, fmt.Errorf("ir/codec/json: expected Path, got null")
	}

	var rawParts []json.RawMessage
	if err := json.Unmarshal(trimmed, &rawParts); err != nil {
		return ir.Path{}, fmt.Errorf("ir/codec/json: expected array of names: %w", err)
	}

	parts := make([]ir.Name, 0, len(rawParts))
	for _, raw := range rawParts {
		name, err := DecodeName(opts, raw)
		if err != nil {
			return ir.Path{}, err
		}
		parts = append(parts, name)
	}

	return ir.PathFromParts(parts), nil
}
