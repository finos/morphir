package json

// Options control JSON encoding/decoding behavior.
//
// Default behavior is to follow the Morphir IR schemas for the selected FormatVersion.
// Options are intended to support additional representations over time (e.g. encoding
// names as strings or URLs) without changing the stable IR domain model.
type Options struct {
	FormatVersion FormatVersion

	// NameEncoding controls how ir.Name values are represented in JSON.
	//
	// When unset, the default is NameAsStringArray (schema-compatible).
	NameEncoding NameEncoding
}

// NameEncoding describes how an ir.Name is represented in JSON.
//
// Today, Morphir-compatible encoding is an array of strings (e.g. ["local","name"]).
// Other encodings may be introduced for tooling convenience but should be opt-in.
type NameEncoding uint8

const (
	// NameAsStringArray encodes a name as a JSON array of strings.
	NameAsStringArray NameEncoding = iota

	// NameAsString encodes a name as a single string (future/opt-in).
	NameAsString

	// NameAsURL encodes a name as a URL-like string (future/opt-in).
	NameAsURL
)

func (o Options) withDefaults() Options {
	out := o
	if out.FormatVersion == 0 {
		out.FormatVersion = FormatV3
	}
	// NameEncoding default is zero value, which we intentionally define as NameAsStringArray.
	return out
}
