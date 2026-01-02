package json

import "fmt"

// FormatVersion represents the Morphir IR JSON formatVersion.
//
// Supported versions correspond to the morphir-dotnet schema set (v1, v2, v3).
// Newer versions may be added over time.
type FormatVersion uint8

const (
	FormatV1 FormatVersion = 1
	FormatV2 FormatVersion = 2
	FormatV3 FormatVersion = 3
)

func (v FormatVersion) String() string {
	switch v {
	case FormatV1:
		return "v1"
	case FormatV2:
		return "v2"
	case FormatV3:
		return "v3"
	default:
		return fmt.Sprintf("v%d", uint8(v))
	}
}

// ParseFormatVersion converts an integer formatVersion value to a FormatVersion.
func ParseFormatVersion(v int) (FormatVersion, error) {
	if v < 0 || v > 255 {
		return 0, fmt.Errorf("ir/codec/json: invalid formatVersion: %d", v)
	}
	fv := FormatVersion(uint8(v))
	switch fv {
	case FormatV1, FormatV2, FormatV3:
		return fv, nil
	default:
		return 0, fmt.Errorf("ir/codec/json: unsupported formatVersion: %d", v)
	}
}
