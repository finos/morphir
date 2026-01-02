package ir

import "math/big"

// Decimal represents an arbitrary-precision decimal value.
//
// Morphir's reference implementation uses Morphir.SDK.Decimal.
//
// In the stable IR we model Decimal as a validated string to:
//   - preserve exact values across JSON round-trips,
//   - avoid premature commitment to a specific decimal library.
//
// Validation currently relies on math/big.Rat parsing.
//
// Note: This type is intentionally small; operations belong in an SDK layer.
type Decimal struct {
	value string
}

// DecimalFromString parses and validates a decimal string.
//
// Returns (Decimal, true) if the string is a valid decimal representation.
func DecimalFromString(s string) (Decimal, bool) {
	if s == "" {
		return Decimal{}, false
	}
	// big.Rat accepts a broad set of numeric formats; we use it as a conservative
	// syntax check and keep the original string for round-trip fidelity.
	var r big.Rat
	if _, ok := r.SetString(s); !ok {
		return Decimal{}, false
	}
	return Decimal{value: s}, true
}

func (d Decimal) String() string {
	return d.value
}

func (d Decimal) Equal(other Decimal) bool {
	return d.value == other.value
}
