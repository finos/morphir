package encoding

// FormatVersion represents the version of the encoding format
type FormatVersion struct {
	Major uint
	Minor uint
	Patch uint
}

type Versioned[T any] struct {
	Version        FormatVersion
	IncludeVersion bool `json:"-"`
	Value          T
}
