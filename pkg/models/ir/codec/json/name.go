package json

import (
	"bytes"
	"encoding/json"
	"fmt"

	ir "github.com/finos/morphir/pkg/models/ir"
)

// EncodeName encodes a Morphir ir.Name to JSON according to the provided options.
//
// By default (schema-compatible), a Name is encoded as a JSON array of strings.
func EncodeName(opts Options, name ir.Name) ([]byte, error) {
	opts = opts.withDefaults()

	switch opts.NameEncoding {
	case NameAsStringArray:
		return json.Marshal(name.Parts())
	case NameAsString:
		return nil, fmt.Errorf("ir/codec/json: NameAsString encoding not implemented")
	case NameAsURL:
		return nil, fmt.Errorf("ir/codec/json: NameAsURL encoding not implemented")
	default:
		return nil, fmt.Errorf("ir/codec/json: unknown NameEncoding: %d", opts.NameEncoding)
	}
}

// DecodeName decodes a Morphir ir.Name from JSON according to the provided options.
//
// By default (schema-compatible), a Name is decoded from a JSON array of strings.
func DecodeName(opts Options, data []byte) (ir.Name, error) {
	opts = opts.withDefaults()

	trimmed := bytes.TrimSpace(data)
	if bytes.Equal(trimmed, []byte("null")) {
		return ir.Name{}, fmt.Errorf("ir/codec/json: expected Name, got null")
	}

	switch opts.NameEncoding {
	case NameAsStringArray:
		var parts []string
		if err := json.Unmarshal(trimmed, &parts); err != nil {
			return ir.Name{}, fmt.Errorf("ir/codec/json: expected array of strings: %w", err)
		}
		return ir.NameFromParts(parts), nil
	case NameAsString:
		return ir.Name{}, fmt.Errorf("ir/codec/json: NameAsString decoding not implemented")
	case NameAsURL:
		return ir.Name{}, fmt.Errorf("ir/codec/json: NameAsURL decoding not implemented")
	default:
		return ir.Name{}, fmt.Errorf("ir/codec/json: unknown NameEncoding: %d", opts.NameEncoding)
	}
}
