package json

import (
	"bytes"
	"encoding/json"
	"fmt"

	ir "github.com/finos/morphir/pkg/models/ir"
)

// EncodeAccessControlled encodes an AccessControlled value using versioned Morphir-compatible JSON.
//
// In Morphir-Elm:
//   - v1: ["public"|"private", value]
//   - v2/v3: {"access":"Public"|"Private","value":value}
func EncodeAccessControlled[A any](opts Options, encodeValue func(A) (json.RawMessage, error), ac ir.AccessControlled[A]) ([]byte, error) {
	opts = opts.withDefaults()
	if encodeValue == nil {
		return nil, fmt.Errorf("codec/json: encodeValue must not be nil")
	}

	valueRaw, err := encodeValue(ac.Value())
	if err != nil {
		return nil, fmt.Errorf("codec/json: encode access-controlled value: %w", err)
	}
	if len(valueRaw) == 0 {
		return nil, fmt.Errorf("codec/json: encodeValue returned empty JSON")
	}

	if opts.FormatVersion == FormatV1 {
		return encodeAccessControlledV1(valueRaw, ac)
	}
	return encodeAccessControlledObj(valueRaw, ac)
}

// DecodeAccessControlled decodes an AccessControlled value using versioned Morphir-compatible JSON.
func DecodeAccessControlled[A any](opts Options, decodeValue func(json.RawMessage) (A, error), data []byte) (ir.AccessControlled[A], error) {
	opts = opts.withDefaults()
	if decodeValue == nil {
		var zero ir.AccessControlled[A]
		return zero, fmt.Errorf("codec/json: decodeValue must not be nil")
	}

	trimmed := bytes.TrimSpace(data)
	if bytes.Equal(trimmed, []byte("null")) {
		var zero ir.AccessControlled[A]
		return zero, fmt.Errorf("codec/json: expected access-controlled value, got null")
	}

	if opts.FormatVersion == FormatV1 {
		return decodeAccessControlledV1(trimmed, decodeValue)
	}
	return decodeAccessControlledObj(trimmed, decodeValue)
}

func encodeAccessControlledV1[A any](valueRaw json.RawMessage, ac ir.AccessControlled[A]) ([]byte, error) {
	tag := "private"
	if ac.Access() == ir.AccessPublic {
		tag = "public"
	}
	tagRaw, err := json.Marshal(tag)
	if err != nil {
		return nil, fmt.Errorf("codec/json: encode access-controlled tag: %w", err)
	}
	encoded, err := json.Marshal([]json.RawMessage{json.RawMessage(tagRaw), valueRaw})
	if err != nil {
		return nil, fmt.Errorf("codec/json: encode access-controlled (v1): %w", err)
	}
	return encoded, nil
}

func encodeAccessControlledObj[A any](valueRaw json.RawMessage, ac ir.AccessControlled[A]) ([]byte, error) {
	access := "Private"
	if ac.Access() == ir.AccessPublic {
		access = "Public"
	}
	obj := map[string]json.RawMessage{
		"access": json.RawMessage(strRaw(access)),
		"value":  valueRaw,
	}
	encoded, err := json.Marshal(obj)
	if err != nil {
		return nil, fmt.Errorf("codec/json: encode access-controlled: %w", err)
	}
	return encoded, nil
}

func decodeAccessControlledV1[A any](trimmed []byte, decodeValue func(json.RawMessage) (A, error)) (ir.AccessControlled[A], error) {
	var parts []json.RawMessage
	if err := json.Unmarshal(trimmed, &parts); err != nil {
		var zero ir.AccessControlled[A]
		return zero, fmt.Errorf("codec/json: decode access-controlled (v1): %w", err)
	}
	if len(parts) != 2 {
		var zero ir.AccessControlled[A]
		return zero, fmt.Errorf("codec/json: decode access-controlled (v1): expected array length 2, got %d", len(parts))
	}
	var tag string
	if err := json.Unmarshal(parts[0], &tag); err != nil {
		var zero ir.AccessControlled[A]
		return zero, fmt.Errorf("codec/json: decode access-controlled tag (v1): %w", err)
	}
	value, err := decodeValue(parts[1])
	if err != nil {
		var zero ir.AccessControlled[A]
		return zero, fmt.Errorf("codec/json: decode access-controlled value (v1): %w", err)
	}
	switch tag {
	case "public":
		return ir.Public(value), nil
	case "private":
		return ir.Private(value), nil
	default:
		var zero ir.AccessControlled[A]
		return zero, fmt.Errorf("codec/json: unknown access-controlled tag: %q", tag)
	}
}

func decodeAccessControlledObj[A any](trimmed []byte, decodeValue func(json.RawMessage) (A, error)) (ir.AccessControlled[A], error) {
	var obj map[string]json.RawMessage
	if err := json.Unmarshal(trimmed, &obj); err != nil {
		var zero ir.AccessControlled[A]
		return zero, fmt.Errorf("codec/json: decode access-controlled: %w", err)
	}
	accessRaw, ok := obj["access"]
	if !ok {
		var zero ir.AccessControlled[A]
		return zero, fmt.Errorf("codec/json: decode access-controlled: missing field 'access'")
	}
	valueRaw, ok := obj["value"]
	if !ok {
		var zero ir.AccessControlled[A]
		return zero, fmt.Errorf("codec/json: decode access-controlled: missing field 'value'")
	}

	var accessStr string
	if err := json.Unmarshal(accessRaw, &accessStr); err != nil {
		var zero ir.AccessControlled[A]
		return zero, fmt.Errorf("codec/json: decode access-controlled access: %w", err)
	}
	value, err := decodeValue(valueRaw)
	if err != nil {
		var zero ir.AccessControlled[A]
		return zero, fmt.Errorf("codec/json: decode access-controlled value: %w", err)
	}
	switch accessStr {
	case "Public":
		return ir.Public(value), nil
	case "Private":
		return ir.Private(value), nil
	default:
		var zero ir.AccessControlled[A]
		return zero, fmt.Errorf("codec/json: unknown access-controlled access: %q", accessStr)
	}
}

func strRaw(s string) []byte {
	b, _ := json.Marshal(s)
	return b
}
