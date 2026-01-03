package json

import (
	"bytes"
	"encoding/json"
	"fmt"

	ir "github.com/finos/morphir-go/pkg/models/ir"
)

// EncodePattern encodes a Morphir IR Pattern using versioned Morphir-compatible JSON.
//
// Tag casing differs by format version:
//   - v1: snake_case (e.g. "wildcard_pattern")
//   - v2/v3: PascalCase (e.g. "WildcardPattern")
func EncodePattern[A any](opts Options, encodeAttributes AttrEncoder[A], pattern ir.Pattern[A]) ([]byte, error) {
	opts = opts.withDefaults()
	raw, err := encodePatternRaw(opts, encodeAttributes, pattern)
	if err != nil {
		return nil, err
	}
	return raw, nil
}

func encodePatternRaw[A any](opts Options, encodeAttributes AttrEncoder[A], pattern ir.Pattern[A]) (json.RawMessage, error) {
	if pattern == nil {
		return nil, fmt.Errorf("codec/json: Pattern must not be null")
	}
	if encodeAttributes == nil {
		return nil, fmt.Errorf("codec/json: encodeAttributes must not be nil")
	}

	switch p := pattern.(type) {
	case ir.WildcardPattern[A]:
		return encodeWildcardPattern(opts, encodeAttributes, p)
	case ir.AsPattern[A]:
		return encodeAsPattern(opts, encodeAttributes, p)
	case ir.TuplePattern[A]:
		return encodeTuplePattern(opts, encodeAttributes, p)
	case ir.ConstructorPattern[A]:
		return encodeConstructorPattern(opts, encodeAttributes, p)
	case ir.EmptyListPattern[A]:
		return encodeEmptyListPattern(opts, encodeAttributes, p)
	case ir.HeadTailPattern[A]:
		return encodeHeadTailPattern(opts, encodeAttributes, p)
	case ir.LiteralPattern[A]:
		return encodeLiteralPattern(opts, encodeAttributes, p)
	case ir.UnitPattern[A]:
		return encodeUnitPattern(opts, encodeAttributes, p)
	default:
		return nil, fmt.Errorf("codec/json: unsupported Pattern variant %T", pattern)
	}
}

func encodeWildcardPattern[A any](opts Options, encodeAttributes AttrEncoder[A], p ir.WildcardPattern[A]) (json.RawMessage, error) {
	tag := tagForPattern(opts.FormatVersion, "WildcardPattern")
	return encodePattern2(opts, encodeAttributes, tag, p.Attributes())
}

func encodeAsPattern[A any](opts Options, encodeAttributes AttrEncoder[A], p ir.AsPattern[A]) (json.RawMessage, error) {
	tag := tagForPattern(opts.FormatVersion, "AsPattern")
	return encodePattern3Plus(opts, encodeAttributes, tag, p.Attributes(), func(parts []json.RawMessage) ([]json.RawMessage, error) {
		subjectRaw, err := encodePatternRaw(opts, encodeAttributes, p.Subject())
		if err != nil {
			return nil, err
		}
		nameRaw, err := EncodeName(opts, p.Name())
		if err != nil {
			return nil, err
		}
		return append(parts, subjectRaw, json.RawMessage(nameRaw)), nil
	})
}

func encodeTuplePattern[A any](opts Options, encodeAttributes AttrEncoder[A], p ir.TuplePattern[A]) (json.RawMessage, error) {
	tag := tagForPattern(opts.FormatVersion, "TuplePattern")
	return encodePattern3Plus(opts, encodeAttributes, tag, p.Attributes(), func(parts []json.RawMessage) ([]json.RawMessage, error) {
		listRaw, err := encodePatternListRaw(opts, encodeAttributes, p.Elements())
		if err != nil {
			return nil, err
		}
		return append(parts, json.RawMessage(listRaw)), nil
	})
}

func encodeConstructorPattern[A any](opts Options, encodeAttributes AttrEncoder[A], p ir.ConstructorPattern[A]) (json.RawMessage, error) {
	tag := tagForPattern(opts.FormatVersion, "ConstructorPattern")
	return encodePattern3Plus(opts, encodeAttributes, tag, p.Attributes(), func(parts []json.RawMessage) ([]json.RawMessage, error) {
		fqRaw, err := EncodeFQName(opts, p.ConstructorName())
		if err != nil {
			return nil, err
		}
		argsRaw, err := encodePatternListRaw(opts, encodeAttributes, p.Args())
		if err != nil {
			return nil, err
		}
		return append(parts, json.RawMessage(fqRaw), json.RawMessage(argsRaw)), nil
	})
}

func encodeEmptyListPattern[A any](opts Options, encodeAttributes AttrEncoder[A], p ir.EmptyListPattern[A]) (json.RawMessage, error) {
	tag := tagForPattern(opts.FormatVersion, "EmptyListPattern")
	return encodePattern2(opts, encodeAttributes, tag, p.Attributes())
}

func encodeHeadTailPattern[A any](opts Options, encodeAttributes AttrEncoder[A], p ir.HeadTailPattern[A]) (json.RawMessage, error) {
	tag := tagForPattern(opts.FormatVersion, "HeadTailPattern")
	return encodePattern3Plus(opts, encodeAttributes, tag, p.Attributes(), func(parts []json.RawMessage) ([]json.RawMessage, error) {
		headRaw, err := encodePatternRaw(opts, encodeAttributes, p.Head())
		if err != nil {
			return nil, err
		}
		tailRaw, err := encodePatternRaw(opts, encodeAttributes, p.Tail())
		if err != nil {
			return nil, err
		}
		return append(parts, headRaw, tailRaw), nil
	})
}

func encodeLiteralPattern[A any](opts Options, encodeAttributes AttrEncoder[A], p ir.LiteralPattern[A]) (json.RawMessage, error) {
	tag := tagForPattern(opts.FormatVersion, "LiteralPattern")
	return encodePattern3Plus(opts, encodeAttributes, tag, p.Attributes(), func(parts []json.RawMessage) ([]json.RawMessage, error) {
		litRaw, err := EncodeLiteral(opts, p.Literal())
		if err != nil {
			return nil, err
		}
		return append(parts, json.RawMessage(litRaw)), nil
	})
}

func encodeUnitPattern[A any](opts Options, encodeAttributes AttrEncoder[A], p ir.UnitPattern[A]) (json.RawMessage, error) {
	tag := tagForPattern(opts.FormatVersion, "UnitPattern")
	return encodePattern2(opts, encodeAttributes, tag, p.Attributes())
}

func encodePatternListRaw[A any](opts Options, encodeAttributes AttrEncoder[A], items []ir.Pattern[A]) ([]byte, error) {
	itemsRaw := make([]json.RawMessage, len(items))
	for i := range items {
		itemRaw, err := encodePatternRaw(opts, encodeAttributes, items[i])
		if err != nil {
			return nil, err
		}
		itemsRaw[i] = itemRaw
	}
	encoded, err := json.Marshal(itemsRaw)
	if err != nil {
		return nil, fmt.Errorf("codec/json: encode list: %w", err)
	}
	return encoded, nil
}

func encodePattern2[A any](opts Options, encodeAttributes AttrEncoder[A], tag string, attrs A) (json.RawMessage, error) {
	parts, err := encodeHeader(opts, encodeAttributes, tag, attrs)
	if err != nil {
		return nil, err
	}
	encoded, err := json.Marshal(parts)
	if err != nil {
		return nil, fmt.Errorf("codec/json: encode %s: %w", tag, err)
	}
	return encoded, nil
}

func encodePattern3Plus[A any](opts Options, encodeAttributes AttrEncoder[A], tag string, attrs A, add func([]json.RawMessage) ([]json.RawMessage, error)) (json.RawMessage, error) {
	parts, err := encodeHeader(opts, encodeAttributes, tag, attrs)
	if err != nil {
		return nil, err
	}
	parts, err = add(parts)
	if err != nil {
		return nil, err
	}
	encoded, err := json.Marshal(parts)
	if err != nil {
		return nil, fmt.Errorf("codec/json: encode %s: %w", tag, err)
	}
	return encoded, nil
}

// DecodePattern decodes a Morphir IR Pattern using versioned Morphir-compatible JSON.
func DecodePattern[A any](opts Options, decodeAttributes AttrDecoder[A], data []byte) (ir.Pattern[A], error) {
	opts = opts.withDefaults()
	trimmed := bytes.TrimSpace(data)
	if bytes.Equal(trimmed, []byte("null")) {
		return nil, fmt.Errorf("codec/json: expected Pattern array, got null")
	}
	if decodeAttributes == nil {
		return nil, fmt.Errorf("codec/json: decodeAttributes must not be nil")
	}

	raw, err := decodePatternHeader(trimmed)
	if err != nil {
		return nil, err
	}

	kind, attrs, err := decodePatternKindAndAttributes(opts, decodeAttributes, raw)
	if err != nil {
		return nil, err
	}

	switch kind {
	case "WildcardPattern":
		return decodeWildcardPattern(attrs, raw)
	case "AsPattern":
		return decodeAsPattern(opts, decodeAttributes, attrs, raw)
	case "TuplePattern":
		return decodeTuplePattern(opts, decodeAttributes, attrs, raw)
	case "ConstructorPattern":
		return decodeConstructorPattern(opts, decodeAttributes, attrs, raw)
	case "EmptyListPattern":
		return decodeEmptyListPattern(attrs, raw)
	case "HeadTailPattern":
		return decodeHeadTailPattern(opts, decodeAttributes, attrs, raw)
	case "LiteralPattern":
		return decodeLiteralPattern(opts, attrs, raw)
	case "UnitPattern":
		return decodeUnitPattern(attrs, raw)
	default:
		return nil, fmt.Errorf("codec/json: unsupported Pattern kind %q", kind)
	}
}

func decodePatternHeader(trimmed []byte) ([]json.RawMessage, error) {
	var raw []json.RawMessage
	if err := json.Unmarshal(trimmed, &raw); err != nil {
		return nil, fmt.Errorf("codec/json: expected Pattern array: %w", err)
	}
	if len(raw) < 2 {
		return nil, fmt.Errorf("codec/json: expected Pattern array with at least 2 elements, got %d", len(raw))
	}
	return raw, nil
}

func decodePatternKindAndAttributes[A any](opts Options, decodeAttributes AttrDecoder[A], raw []json.RawMessage) (string, A, error) {
	var tag string
	if err := json.Unmarshal(raw[0], &tag); err != nil {
		var zero A
		return "", zero, fmt.Errorf("codec/json: invalid Pattern tag: %w", err)
	}
	kind, err := kindFromPatternTag(opts.FormatVersion, tag)
	if err != nil {
		var zero A
		return "", zero, err
	}
	attrs, err := decodeAttributes(raw[1])
	if err != nil {
		var zero A
		return "", zero, fmt.Errorf("codec/json: decode attributes: %w", err)
	}
	return kind, attrs, nil
}

func decodeWildcardPattern[A any](attrs A, raw []json.RawMessage) (ir.Pattern[A], error) {
	if len(raw) != 2 {
		return nil, fmt.Errorf("codec/json: WildcardPattern expects 2 elements, got %d", len(raw))
	}
	return ir.NewWildcardPattern(attrs), nil
}

func decodeAsPattern[A any](opts Options, decodeAttributes AttrDecoder[A], attrs A, raw []json.RawMessage) (ir.Pattern[A], error) {
	if len(raw) != 4 {
		return nil, fmt.Errorf("codec/json: AsPattern expects 4 elements, got %d", len(raw))
	}
	subject, err := DecodePattern(opts, decodeAttributes, raw[2])
	if err != nil {
		return nil, fmt.Errorf("codec/json: decode AsPattern subject: %w", err)
	}
	name, err := DecodeName(opts, raw[3])
	if err != nil {
		return nil, err
	}
	return ir.NewAsPattern(attrs, subject, name), nil
}

func decodeTuplePattern[A any](opts Options, decodeAttributes AttrDecoder[A], attrs A, raw []json.RawMessage) (ir.Pattern[A], error) {
	if len(raw) != 3 {
		return nil, fmt.Errorf("codec/json: TuplePattern expects 3 elements, got %d", len(raw))
	}
	items, err := decodePatternList(opts, decodeAttributes, raw[2])
	if err != nil {
		return nil, fmt.Errorf("codec/json: decode TuplePattern elements: %w", err)
	}
	return ir.NewTuplePattern(attrs, items), nil
}

func decodeConstructorPattern[A any](opts Options, decodeAttributes AttrDecoder[A], attrs A, raw []json.RawMessage) (ir.Pattern[A], error) {
	if len(raw) != 4 {
		return nil, fmt.Errorf("codec/json: ConstructorPattern expects 4 elements, got %d", len(raw))
	}
	fq, err := DecodeFQName(opts, raw[2])
	if err != nil {
		return nil, err
	}
	args, err := decodePatternList(opts, decodeAttributes, raw[3])
	if err != nil {
		return nil, fmt.Errorf("codec/json: decode ConstructorPattern args: %w", err)
	}
	return ir.NewConstructorPattern(attrs, fq, args), nil
}

func decodeEmptyListPattern[A any](attrs A, raw []json.RawMessage) (ir.Pattern[A], error) {
	if len(raw) != 2 {
		return nil, fmt.Errorf("codec/json: EmptyListPattern expects 2 elements, got %d", len(raw))
	}
	return ir.NewEmptyListPattern(attrs), nil
}

func decodeHeadTailPattern[A any](opts Options, decodeAttributes AttrDecoder[A], attrs A, raw []json.RawMessage) (ir.Pattern[A], error) {
	if len(raw) != 4 {
		return nil, fmt.Errorf("codec/json: HeadTailPattern expects 4 elements, got %d", len(raw))
	}
	head, err := DecodePattern(opts, decodeAttributes, raw[2])
	if err != nil {
		return nil, fmt.Errorf("codec/json: decode HeadTailPattern head: %w", err)
	}
	tail, err := DecodePattern(opts, decodeAttributes, raw[3])
	if err != nil {
		return nil, fmt.Errorf("codec/json: decode HeadTailPattern tail: %w", err)
	}
	return ir.NewHeadTailPattern(attrs, head, tail), nil
}

func decodeLiteralPattern[A any](opts Options, attrs A, raw []json.RawMessage) (ir.Pattern[A], error) {
	if len(raw) != 3 {
		return nil, fmt.Errorf("codec/json: LiteralPattern expects 3 elements, got %d", len(raw))
	}
	lit, err := DecodeLiteral(opts, raw[2])
	if err != nil {
		return nil, err
	}
	return ir.NewLiteralPattern(attrs, lit), nil
}

func decodeUnitPattern[A any](attrs A, raw []json.RawMessage) (ir.Pattern[A], error) {
	if len(raw) != 2 {
		return nil, fmt.Errorf("codec/json: UnitPattern expects 2 elements, got %d", len(raw))
	}
	return ir.NewUnitPattern(attrs), nil
}

func decodePatternList[A any](opts Options, decodeAttributes AttrDecoder[A], raw json.RawMessage) ([]ir.Pattern[A], error) {
	var items []json.RawMessage
	if err := json.Unmarshal(raw, &items); err != nil {
		return nil, fmt.Errorf("codec/json: expected list: %w", err)
	}
	out := make([]ir.Pattern[A], len(items))
	for i := range items {
		p, err := DecodePattern(opts, decodeAttributes, items[i])
		if err != nil {
			return nil, err
		}
		out[i] = p
	}
	return out, nil
}

func tagForPattern(version FormatVersion, kind string) string {
	if version == FormatV1 {
		switch kind {
		case "WildcardPattern":
			return "wildcard_pattern"
		case "AsPattern":
			return "as_pattern"
		case "TuplePattern":
			return "tuple_pattern"
		case "ConstructorPattern":
			return "constructor_pattern"
		case "EmptyListPattern":
			return "empty_list_pattern"
		case "HeadTailPattern":
			return "head_tail_pattern"
		case "LiteralPattern":
			return "literal_pattern"
		case "UnitPattern":
			return "unit_pattern"
		default:
			return kind
		}
	}
	return kind
}

func kindFromPatternTag(version FormatVersion, tag string) (string, error) {
	if version == FormatV1 {
		switch tag {
		case "wildcard_pattern":
			return "WildcardPattern", nil
		case "as_pattern":
			return "AsPattern", nil
		case "tuple_pattern":
			return "TuplePattern", nil
		case "constructor_pattern":
			return "ConstructorPattern", nil
		case "empty_list_pattern":
			return "EmptyListPattern", nil
		case "head_tail_pattern":
			return "HeadTailPattern", nil
		case "literal_pattern":
			return "LiteralPattern", nil
		case "unit_pattern":
			return "UnitPattern", nil
		default:
			return "", fmt.Errorf("codec/json: unknown v1 Pattern tag %q", tag)
		}
	}

	// v2/v3
	switch tag {
	case "WildcardPattern", "AsPattern", "TuplePattern", "ConstructorPattern", "EmptyListPattern", "HeadTailPattern", "LiteralPattern", "UnitPattern":
		return tag, nil
	default:
		return "", fmt.Errorf("codec/json: unknown Pattern tag %q", tag)
	}
}
