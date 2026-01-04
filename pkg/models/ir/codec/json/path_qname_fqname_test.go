package json

import (
	"testing"

	ir "github.com/finos/morphir/pkg/models/ir"
)

const expectedError = "expected error"

func TestPathDefaultEncodesAsArrayOfNames(t *testing.T) {
	path := ir.PathFromParts([]ir.Name{ir.NameFromParts([]string{"morphir"}), ir.NameFromParts([]string{"s", "d", "k"})})

	data, err := EncodePath(Options{FormatVersion: FormatV3}, path)
	if err != nil {
		t.Fatalf("EncodePath: %v", err)
	}

	decoded, err := DecodePath(Options{FormatVersion: FormatV3}, data)
	if err != nil {
		t.Fatalf("DecodePath: %v", err)
	}

	if !path.Equal(decoded) {
		t.Fatalf("expected roundtrip equality; got %v", decoded.Parts())
	}
}

func TestQNameDefaultEncodesAsTuple(t *testing.T) {
	q := ir.QNameFromParts(
		ir.PathFromParts([]ir.Name{ir.NameFromParts([]string{"Fantastic"}), ir.NameFromParts([]string{"Module"})}),
		ir.NameFromParts([]string{"Amazing", "Local", "Name"}),
	)

	data, err := EncodeQName(Options{FormatVersion: FormatV3}, q)
	if err != nil {
		t.Fatalf("EncodeQName: %v", err)
	}

	decoded, err := DecodeQName(Options{FormatVersion: FormatV3}, data)
	if err != nil {
		t.Fatalf("DecodeQName: %v", err)
	}

	if !q.Equal(decoded) {
		mp, ln := decoded.Parts()
		t.Fatalf("expected roundtrip equality; got (%v,%v)", mp.Parts(), ln.Parts())
	}
}

func TestFQNameDefaultEncodesAsTriple(t *testing.T) {
	f := ir.FQNameFromParts(
		ir.PathFromParts([]ir.Name{ir.NameFromParts([]string{"Excellent"}), ir.NameFromParts([]string{"Package"})}),
		ir.PathFromParts([]ir.Name{ir.NameFromParts([]string{"Fantastic"}), ir.NameFromParts([]string{"Module"})}),
		ir.NameFromParts([]string{"Amazing", "Local", "Name"}),
	)

	data, err := EncodeFQName(Options{FormatVersion: FormatV3}, f)
	if err != nil {
		t.Fatalf("EncodeFQName: %v", err)
	}

	decoded, err := DecodeFQName(Options{FormatVersion: FormatV3}, data)
	if err != nil {
		t.Fatalf("DecodeFQName: %v", err)
	}

	if !f.Equal(decoded) {
		pp, mp, ln := decoded.Parts()
		t.Fatalf("expected roundtrip equality; got (%v,%v,%v)", pp.Parts(), mp.Parts(), ln.Parts())
	}
}

func TestPathQNameFQNameUnsupportedNameEncodingsFail(t *testing.T) {
	opts := Options{NameEncoding: NameAsString}

	if _, err := EncodePath(opts, ir.PathFromParts([]ir.Name{ir.NameFromParts([]string{"x"})})); err == nil {
		t.Fatal(expectedError)
	}
	if _, err := EncodeQName(opts, ir.QNameFromParts(ir.PathFromParts(nil), ir.NameFromParts([]string{"x"}))); err == nil {
		t.Fatal(expectedError)
	}
	if _, err := EncodeFQName(opts, ir.FQNameFromParts(ir.PathFromParts(nil), ir.PathFromParts(nil), ir.NameFromParts([]string{"x"}))); err == nil {
		t.Fatal(expectedError)
	}
}
