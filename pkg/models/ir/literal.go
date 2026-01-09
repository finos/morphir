package ir

// Literal corresponds to Morphir.IR.Literal.
//
// JSON encoding is versioned and implemented in the codec layer.
// See pkg/models/ir/codec/json.
//
// Literal is a sum type; concrete variants include BoolLiteral, CharLiteral, etc.
type Literal interface {
	isLiteral()
}

// BoolLiteral corresponds to: BoolLiteral Bool
//
// Represents a boolean literal.
type BoolLiteral struct {
	value bool
}

// NewBoolLiteral creates a new boolean literal with the given value.
func NewBoolLiteral(value bool) Literal {
	return BoolLiteral{value: value}
}

func (BoolLiteral) isLiteral() {
	// Marker method for the Literal sum type.
}

// Value returns the boolean value of this literal.
func (l BoolLiteral) Value() bool {
	return l.value
}

// CharLiteral corresponds to: CharLiteral Char
//
// Represents a character literal.
type CharLiteral struct {
	value rune
}

// NewCharLiteral creates a new character literal with the given rune value.
func NewCharLiteral(value rune) Literal {
	return CharLiteral{value: value}
}

func (CharLiteral) isLiteral() {
	// Marker method for the Literal sum type.
}

// Value returns the rune value of this character literal.
func (l CharLiteral) Value() rune {
	return l.value
}

// StringLiteral corresponds to: StringLiteral String
//
// Represents a string literal.
type StringLiteral struct {
	value string
}

// NewStringLiteral creates a new string literal with the given value.
func NewStringLiteral(value string) Literal {
	return StringLiteral{value: value}
}

func (StringLiteral) isLiteral() {
	// Marker method for the Literal sum type.
}

// Value returns the string value of this literal.
func (l StringLiteral) Value() string {
	return l.value
}

// WholeNumberLiteral corresponds to: WholeNumberLiteral Int
//
// Represents a whole number (integer) literal.
type WholeNumberLiteral struct {
	value int64
}

// NewWholeNumberLiteral creates a new whole number (integer) literal with the given value.
func NewWholeNumberLiteral(value int64) Literal {
	return WholeNumberLiteral{value: value}
}

func (WholeNumberLiteral) isLiteral() {
	// Marker method for the Literal sum type.
}

// Value returns the int64 value of this whole number literal.
func (l WholeNumberLiteral) Value() int64 {
	return l.value
}

// FloatLiteral corresponds to: FloatLiteral Float
//
// Represents a floating-point number literal.
type FloatLiteral struct {
	value float64
}

// NewFloatLiteral creates a new floating-point literal with the given value.
func NewFloatLiteral(value float64) Literal {
	return FloatLiteral{value: value}
}

func (FloatLiteral) isLiteral() {
	// Marker method for the Literal sum type.
}

// Value returns the float64 value of this floating-point literal.
func (l FloatLiteral) Value() float64 {
	return l.value
}

// DecimalLiteral corresponds to: DecimalLiteral Decimal
//
// Represents an arbitrary-precision decimal literal.
type DecimalLiteral struct {
	value Decimal
}

// NewDecimalLiteral creates a new arbitrary-precision decimal literal with the given value.
func NewDecimalLiteral(value Decimal) Literal {
	return DecimalLiteral{value: value}
}

func (DecimalLiteral) isLiteral() {
	// Marker method for the Literal sum type.
}

// Value returns the Decimal value of this decimal literal.
func (l DecimalLiteral) Value() Decimal {
	return l.value
}

// EqualLiteral compares two Literal values structurally.
func EqualLiteral(left Literal, right Literal) bool {
	if left == nil || right == nil {
		return left == right
	}

	switch l := left.(type) {
	case BoolLiteral:
		r, ok := right.(BoolLiteral)
		return ok && l.value == r.value
	case CharLiteral:
		r, ok := right.(CharLiteral)
		return ok && l.value == r.value
	case StringLiteral:
		r, ok := right.(StringLiteral)
		return ok && l.value == r.value
	case WholeNumberLiteral:
		r, ok := right.(WholeNumberLiteral)
		return ok && l.value == r.value
	case FloatLiteral:
		r, ok := right.(FloatLiteral)
		return ok && l.value == r.value
	case DecimalLiteral:
		r, ok := right.(DecimalLiteral)
		return ok && l.value.Equal(r.value)
	default:
		return false
	}
}
