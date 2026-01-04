package json

import (
	"bytes"
	"encoding/json"
	"fmt"
	"unicode/utf8"

	ir "github.com/finos/morphir/pkg/models/ir"
)

const (
	literalExpectedArrayF = "codec/json: expected Literal array: %w"
	literalUnknownTypeF   = "codec/json: unknown literal type: %s"
)

// EncodeLiteral encodes a Morphir literal using Morphir-compatible versioned JSON.
//
// Tag casing differs by format version:
//   - v1: snake_case (e.g. "bool_literal")
//   - v2/v3: PascalCase (e.g. "BoolLiteral")
func EncodeLiteral(opts Options, lit ir.Literal) ([]byte, error) {
	if lit == nil {
		return nil, fmt.Errorf("codec/json: expected Literal value, got null")
	}

	switch v := lit.(type) {
	case ir.BoolLiteral:
		tag := "BoolLiteral"
		if opts.FormatVersion == FormatV1 {
			tag = "bool_literal"
		}
		return json.Marshal([]any{tag, v.Value()})
	case ir.CharLiteral:
		tag := "CharLiteral"
		if opts.FormatVersion == FormatV1 {
			tag = "char_literal"
		}
		return json.Marshal([]any{tag, string(v.Value())})
	case ir.StringLiteral:
		tag := "StringLiteral"
		if opts.FormatVersion == FormatV1 {
			tag = "string_literal"
		}
		return json.Marshal([]any{tag, v.Value()})
	case ir.WholeNumberLiteral:
		tag := "WholeNumberLiteral"
		if opts.FormatVersion == FormatV1 {
			tag = "int_literal"
		}
		return json.Marshal([]any{tag, v.Value()})
	case ir.FloatLiteral:
		tag := "FloatLiteral"
		if opts.FormatVersion == FormatV1 {
			tag = "float_literal"
		}
		return json.Marshal([]any{tag, v.Value()})
	case ir.DecimalLiteral:
		tag := "DecimalLiteral"
		if opts.FormatVersion == FormatV1 {
			tag = "decimal_literal"
		}
		return json.Marshal([]any{tag, v.Value().String()})
	default:
		return nil, fmt.Errorf("codec/json: unsupported Literal variant %T", lit)
	}
}

// DecodeLiteral decodes a Morphir literal using Morphir-compatible versioned JSON.
func DecodeLiteral(opts Options, data []byte) (ir.Literal, error) {
	trimmed := bytes.TrimSpace(data)
	if len(trimmed) == 0 || bytes.Equal(trimmed, []byte("null")) {
		return nil, fmt.Errorf("codec/json: expected Literal value, got null")
	}

	var raw []json.RawMessage
	if err := json.Unmarshal(trimmed, &raw); err != nil {
		return nil, fmt.Errorf(literalExpectedArrayF, err)
	}
	if len(raw) != 2 {
		return nil, fmt.Errorf("codec/json: expected Literal array length 2, got %d", len(raw))
	}

	var tag string
	if err := json.Unmarshal(raw[0], &tag); err != nil {
		return nil, fmt.Errorf("codec/json: expected Literal tag string: %w", err)
	}

	switch opts.FormatVersion {
	case FormatV1:
		return decodeLiteralV1(tag, raw[1])
	case FormatV2, FormatV3:
		return decodeLiteralV2Plus(tag, raw[1])
	default:
		return nil, fmt.Errorf("codec/json: unsupported formatVersion: %d", opts.FormatVersion)
	}
}

func decodeLiteralV1(tag string, value json.RawMessage) (ir.Literal, error) {
	switch tag {
	case "bool_literal":
		var b bool
		if err := json.Unmarshal(value, &b); err != nil {
			return nil, fmt.Errorf("codec/json: decode bool_literal: %w", err)
		}
		return ir.NewBoolLiteral(b), nil
	case "char_literal":
		ch, err := decodeSingleRuneString(value)
		if err != nil {
			return nil, fmt.Errorf("codec/json: decode char_literal: %w", err)
		}
		return ir.NewCharLiteral(ch), nil
	case "string_literal":
		var s string
		if err := json.Unmarshal(value, &s); err != nil {
			return nil, fmt.Errorf("codec/json: decode string_literal: %w", err)
		}
		return ir.NewStringLiteral(s), nil
	case "int_literal":
		var n int64
		if err := json.Unmarshal(value, &n); err != nil {
			return nil, fmt.Errorf("codec/json: decode int_literal: %w", err)
		}
		return ir.NewWholeNumberLiteral(n), nil
	case "float_literal":
		var f float64
		if err := json.Unmarshal(value, &f); err != nil {
			return nil, fmt.Errorf("codec/json: decode float_literal: %w", err)
		}
		return ir.NewFloatLiteral(f), nil
	case "decimal_literal":
		d, err := decodeDecimal(value)
		if err != nil {
			return nil, fmt.Errorf("codec/json: decode decimal_literal: %w", err)
		}
		return ir.NewDecimalLiteral(d), nil
	default:
		return nil, fmt.Errorf(literalUnknownTypeF, tag)
	}
}

func decodeLiteralV2Plus(tag string, value json.RawMessage) (ir.Literal, error) {
	switch tag {
	case "BoolLiteral":
		var b bool
		if err := json.Unmarshal(value, &b); err != nil {
			return nil, fmt.Errorf("codec/json: decode BoolLiteral: %w", err)
		}
		return ir.NewBoolLiteral(b), nil
	case "CharLiteral":
		ch, err := decodeSingleRuneString(value)
		if err != nil {
			return nil, fmt.Errorf("codec/json: decode CharLiteral: %w", err)
		}
		return ir.NewCharLiteral(ch), nil
	case "StringLiteral":
		var s string
		if err := json.Unmarshal(value, &s); err != nil {
			return nil, fmt.Errorf("codec/json: decode StringLiteral: %w", err)
		}
		return ir.NewStringLiteral(s), nil
	case "WholeNumberLiteral":
		var n int64
		if err := json.Unmarshal(value, &n); err != nil {
			return nil, fmt.Errorf("codec/json: decode WholeNumberLiteral: %w", err)
		}
		return ir.NewWholeNumberLiteral(n), nil
	case "FloatLiteral":
		var f float64
		if err := json.Unmarshal(value, &f); err != nil {
			return nil, fmt.Errorf("codec/json: decode FloatLiteral: %w", err)
		}
		return ir.NewFloatLiteral(f), nil
	case "DecimalLiteral":
		d, err := decodeDecimal(value)
		if err != nil {
			return nil, fmt.Errorf("codec/json: decode DecimalLiteral: %w", err)
		}
		return ir.NewDecimalLiteral(d), nil
	default:
		return nil, fmt.Errorf(literalUnknownTypeF, tag)
	}
}

func decodeSingleRuneString(raw json.RawMessage) (rune, error) {
	var s string
	if err := json.Unmarshal(raw, &s); err != nil {
		return 0, err
	}
	if s == "" {
		return 0, fmt.Errorf("single char expected")
	}
	r, size := utf8.DecodeRuneInString(s)
	if r == utf8.RuneError && size == 1 {
		return 0, fmt.Errorf("invalid utf8")
	}
	if size != len(s) {
		return 0, fmt.Errorf("single char expected")
	}
	return r, nil
}

func decodeDecimal(raw json.RawMessage) (ir.Decimal, error) {
	var s string
	if err := json.Unmarshal(raw, &s); err != nil {
		return ir.Decimal{}, err
	}
	dec, ok := ir.DecimalFromString(s)
	if !ok {
		return ir.Decimal{}, fmt.Errorf("invalid decimal: %q", s)
	}
	return dec, nil
}
