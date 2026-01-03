package json

import (
	"bytes"
	"encoding/json"
	"fmt"

	ir "github.com/finos/morphir-go/pkg/models/ir"
)

// EncodeDocumented encodes a Documented value using Morphir-compatible JSON.
//
// In Morphir-Elm: { "doc": string, "value": value }
func EncodeDocumented[A any](opts Options, encodeValue func(A) (json.RawMessage, error), doc ir.Documented[A]) ([]byte, error) {
	_ = opts.withDefaults() // opts reserved for future format-version-specific encoding
	if encodeValue == nil {
		return nil, fmt.Errorf("codec/json: encodeValue must not be nil")
	}

	valueRaw, err := encodeValue(doc.Value())
	if err != nil {
		return nil, fmt.Errorf("codec/json: encode documented value: %w", err)
	}
	if len(valueRaw) == 0 {
		return nil, fmt.Errorf("codec/json: encodeValue returned empty JSON")
	}

	docStr := doc.Doc()
	docRaw, err := json.Marshal(docStr)
	if err != nil {
		return nil, fmt.Errorf("codec/json: encode documented doc: %w", err)
	}

	obj := map[string]json.RawMessage{
		"doc":   json.RawMessage(docRaw),
		"value": valueRaw,
	}
	encoded, err := json.Marshal(obj)
	if err != nil {
		return nil, fmt.Errorf("codec/json: encode documented: %w", err)
	}
	return encoded, nil
}

// DecodeDocumented decodes a Documented value using Morphir-compatible JSON.
func DecodeDocumented[A any](opts Options, decodeValue func(json.RawMessage) (A, error), data []byte) (ir.Documented[A], error) {
	_ = opts.withDefaults() // opts reserved for future format-version-specific decoding
	if decodeValue == nil {
		var zero ir.Documented[A]
		return zero, fmt.Errorf("codec/json: decodeValue must not be nil")
	}

	trimmed := bytes.TrimSpace(data)
	if bytes.Equal(trimmed, []byte("null")) {
		var zero ir.Documented[A]
		return zero, fmt.Errorf("codec/json: expected documented value, got null")
	}

	var obj map[string]json.RawMessage
	if err := json.Unmarshal(trimmed, &obj); err != nil {
		var zero ir.Documented[A]
		return zero, fmt.Errorf("codec/json: decode documented: %w", err)
	}

	docRaw, ok := obj["doc"]
	if !ok {
		var zero ir.Documented[A]
		return zero, fmt.Errorf("codec/json: decode documented: missing field 'doc'")
	}
	valueRaw, ok := obj["value"]
	if !ok {
		var zero ir.Documented[A]
		return zero, fmt.Errorf("codec/json: decode documented: missing field 'value'")
	}

	var docStr string
	if err := json.Unmarshal(docRaw, &docStr); err != nil {
		var zero ir.Documented[A]
		return zero, fmt.Errorf("codec/json: decode documented doc: %w", err)
	}

	value, err := decodeValue(valueRaw)
	if err != nil {
		var zero ir.Documented[A]
		return zero, fmt.Errorf("codec/json: decode documented value: %w", err)
	}

	return ir.NewDocumented(docStr, value), nil
}

// encodeDocumentedRaw is an internal helper for encoding Documented values.
func encodeDocumentedRaw[A any](opts Options, encodeValue func(A) (json.RawMessage, error), doc ir.Documented[A]) (json.RawMessage, error) {
	data, err := EncodeDocumented(opts, encodeValue, doc)
	if err != nil {
		return nil, err
	}
	return json.RawMessage(data), nil
}
