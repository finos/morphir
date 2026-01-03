package json

import (
	"bytes"
	"encoding/json"
	"fmt"

	ir "github.com/finos/morphir-go/pkg/models/ir"
)

// EncodeFQName encodes a Morphir ir.FQName to JSON according to the provided options.
//
// Schema-compatible encoding is a JSON array of length 3: [packagePath, modulePath, localName].
func EncodeFQName(opts Options, fqname ir.FQName) ([]byte, error) {
	opts = opts.withDefaults()

	pp, mp, ln := fqname.Parts()
	ppBytes, err := EncodePath(opts, pp)
	if err != nil {
		return nil, err
	}
	mpBytes, err := EncodePath(opts, mp)
	if err != nil {
		return nil, err
	}
	lnBytes, err := EncodeName(opts, ln)
	if err != nil {
		return nil, err
	}

	return json.Marshal(
		[]json.RawMessage{
			json.RawMessage(ppBytes),
			json.RawMessage(mpBytes),
			json.RawMessage(lnBytes),
		},
	)
}

// DecodeFQName decodes a Morphir ir.FQName from JSON according to the provided options.
//
// Schema-compatible decoding expects a JSON array of length 3: [packagePath, modulePath, localName].
func DecodeFQName(opts Options, data []byte) (ir.FQName, error) {
	opts = opts.withDefaults()

	trimmed := bytes.TrimSpace(data)
	if bytes.Equal(trimmed, []byte("null")) {
		return ir.FQName{}, fmt.Errorf("ir/codec/json: expected FQName, got null")
	}

	var raw []json.RawMessage
	if err := json.Unmarshal(trimmed, &raw); err != nil {
		return ir.FQName{}, fmt.Errorf("ir/codec/json: expected [packagePath, modulePath, localName]: %w", err)
	}
	if len(raw) != 3 {
		return ir.FQName{}, fmt.Errorf("ir/codec/json: expected FQName array length 3, got %d", len(raw))
	}

	pp, err := DecodePath(opts, raw[0])
	if err != nil {
		return ir.FQName{}, err
	}
	mp, err := DecodePath(opts, raw[1])
	if err != nil {
		return ir.FQName{}, err
	}
	ln, err := DecodeName(opts, raw[2])
	if err != nil {
		return ir.FQName{}, err
	}

	return ir.FQNameFromParts(pp, mp, ln), nil
}
