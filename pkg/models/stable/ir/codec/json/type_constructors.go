package json

import (
	"bytes"
	"encoding/json"
	"fmt"

	ir "github.com/finos/morphir-go/pkg/models/stable/ir"
)

// EncodeTypeConstructors encodes Morphir type constructors using Morphir-compatible JSON.
//
// In Morphir-Elm (all current versions):
//
//	Constructors a is encoded as a list of [ ctorName, ctorArgs ]
//	where ctorArgs is a list of [ argName, argType ].
func EncodeTypeConstructors[A any](opts Options, encodeAttributes AttrEncoder[A], ctors ir.TypeConstructors[A]) ([]byte, error) {
	opts = opts.withDefaults()
	raw, err := encodeTypeConstructorsRaw(opts, encodeAttributes, ctors)
	if err != nil {
		return nil, err
	}
	return raw, nil
}

func encodeTypeConstructorsRaw[A any](opts Options, encodeAttributes AttrEncoder[A], ctors ir.TypeConstructors[A]) (json.RawMessage, error) {
	if encodeAttributes == nil {
		return nil, fmt.Errorf("codec/json: encodeAttributes must not be nil")
	}

	items := make([]json.RawMessage, len(ctors))
	for i := range ctors {
		ctor := ctors[i]
		nameRaw, err := EncodeName(opts, ctor.Name())
		if err != nil {
			return nil, err
		}
		argsRaw, err := encodeTypeConstructorArgsRaw(opts, encodeAttributes, ctor.Args())
		if err != nil {
			return nil, err
		}
		encoded, err := json.Marshal([]json.RawMessage{json.RawMessage(nameRaw), argsRaw})
		if err != nil {
			return nil, fmt.Errorf("codec/json: encode constructor: %w", err)
		}
		items[i] = encoded
	}

	encoded, err := json.Marshal(items)
	if err != nil {
		return nil, fmt.Errorf("codec/json: encode constructors: %w", err)
	}
	return encoded, nil
}

func encodeTypeConstructorArgsRaw[A any](opts Options, encodeAttributes AttrEncoder[A], args ir.TypeConstructorArgs[A]) (json.RawMessage, error) {
	items := make([]json.RawMessage, len(args))
	for i := range args {
		arg := args[i]
		nameRaw, err := EncodeName(opts, arg.Name())
		if err != nil {
			return nil, err
		}
		tpeRaw, err := encodeTypeRaw(opts, encodeAttributes, arg.Type())
		if err != nil {
			return nil, err
		}
		encoded, err := json.Marshal([]json.RawMessage{json.RawMessage(nameRaw), tpeRaw})
		if err != nil {
			return nil, fmt.Errorf("codec/json: encode constructor arg: %w", err)
		}
		items[i] = encoded
	}
	encoded, err := json.Marshal(items)
	if err != nil {
		return nil, fmt.Errorf("codec/json: encode constructor args: %w", err)
	}
	return encoded, nil
}

// DecodeTypeConstructors decodes Morphir type constructors using Morphir-compatible JSON.
func DecodeTypeConstructors[A any](opts Options, decodeAttributes AttrDecoder[A], data []byte) (ir.TypeConstructors[A], error) {
	opts = opts.withDefaults()
	trimmed := bytes.TrimSpace(data)
	if bytes.Equal(trimmed, []byte("null")) {
		return nil, fmt.Errorf("codec/json: expected constructors array, got null")
	}
	if decodeAttributes == nil {
		return nil, fmt.Errorf("codec/json: decodeAttributes must not be nil")
	}

	var items []json.RawMessage
	if err := json.Unmarshal(trimmed, &items); err != nil {
		return nil, fmt.Errorf("codec/json: decode constructors: %w", err)
	}
	ctors := make(ir.TypeConstructors[A], len(items))
	for i := range items {
		ctor, err := decodeTypeConstructor(opts, decodeAttributes, items[i])
		if err != nil {
			return nil, err
		}
		ctors[i] = ctor
	}
	return ctors, nil
}

func decodeTypeConstructor[A any](opts Options, decodeAttributes AttrDecoder[A], data json.RawMessage) (ir.TypeConstructor[A], error) {
	var parts []json.RawMessage
	if err := json.Unmarshal(bytes.TrimSpace(data), &parts); err != nil {
		return ir.TypeConstructor[A]{}, fmt.Errorf("codec/json: decode constructor: %w", err)
	}
	if len(parts) != 2 {
		return ir.TypeConstructor[A]{}, fmt.Errorf("codec/json: decode constructor: expected array length 2, got %d", len(parts))
	}
	name, err := DecodeName(opts, parts[0])
	if err != nil {
		return ir.TypeConstructor[A]{}, err
	}
	args, err := decodeTypeConstructorArgs(opts, decodeAttributes, parts[1])
	if err != nil {
		return ir.TypeConstructor[A]{}, err
	}
	return ir.TypeConstructorFromParts[A](name, args), nil
}

func decodeTypeConstructorArgs[A any](opts Options, decodeAttributes AttrDecoder[A], data json.RawMessage) (ir.TypeConstructorArgs[A], error) {
	var items []json.RawMessage
	if err := json.Unmarshal(bytes.TrimSpace(data), &items); err != nil {
		return nil, fmt.Errorf("codec/json: decode constructor args: %w", err)
	}
	args := make(ir.TypeConstructorArgs[A], len(items))
	for i := range items {
		var pair []json.RawMessage
		if err := json.Unmarshal(bytes.TrimSpace(items[i]), &pair); err != nil {
			return nil, fmt.Errorf("codec/json: decode constructor arg: %w", err)
		}
		if len(pair) != 2 {
			return nil, fmt.Errorf("codec/json: decode constructor arg: expected array length 2, got %d", len(pair))
		}
		name, err := DecodeName(opts, pair[0])
		if err != nil {
			return nil, err
		}
		tpe, err := DecodeType(opts, decodeAttributes, pair[1])
		if err != nil {
			return nil, err
		}
		args[i] = ir.TypeConstructorArgFromParts[A](name, tpe)
	}
	return args, nil
}
