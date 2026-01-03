package json

import (
	"bytes"
	"encoding/json"
	"fmt"

	ir "github.com/finos/morphir-go/pkg/models/ir"
)

// EncodeQName encodes a Morphir ir.QName to JSON according to the provided options.
//
// Schema-compatible encoding is a JSON array of length 2: [modulePath, localName].
func EncodeQName(opts Options, qname ir.QName) ([]byte, error) {
	opts = opts.withDefaults()

	mp, ln := qname.Parts()
	mpBytes, err := EncodePath(opts, mp)
	if err != nil {
		return nil, err
	}
	lnBytes, err := EncodeName(opts, ln)
	if err != nil {
		return nil, err
	}

	return json.Marshal([]json.RawMessage{json.RawMessage(mpBytes), json.RawMessage(lnBytes)})
}

// DecodeQName decodes a Morphir ir.QName from JSON according to the provided options.
//
// Schema-compatible decoding expects a JSON array of length 2: [modulePath, localName].
func DecodeQName(opts Options, data []byte) (ir.QName, error) {
	opts = opts.withDefaults()

	trimmed := bytes.TrimSpace(data)
	if bytes.Equal(trimmed, []byte("null")) {
		return ir.QName{}, fmt.Errorf("ir/codec/json: expected QName, got null")
	}

	var raw []json.RawMessage
	if err := json.Unmarshal(trimmed, &raw); err != nil {
		return ir.QName{}, fmt.Errorf("ir/codec/json: expected [modulePath, localName]: %w", err)
	}
	if len(raw) != 2 {
		return ir.QName{}, fmt.Errorf("ir/codec/json: expected QName array length 2, got %d", len(raw))
	}

	mp, err := DecodePath(opts, raw[0])
	if err != nil {
		return ir.QName{}, err
	}
	ln, err := DecodeName(opts, raw[1])
	if err != nil {
		return ir.QName{}, err
	}

	return ir.QNameFromParts(mp, ln), nil
}
