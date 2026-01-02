package ir

import "fmt"

// Value represents the Morphir IR Value tree.
//
// In the upstream Morphir IR (Elm), Value is parameterized by two attribute types:
//   - TA: type attributes (attached to types within the value)
//   - VA: value attributes (attached to each value node)
//
// Those attributes are carried at every node (e.g. source locations, inferred types).
// In Go we model that with type parameters.
//
// JSON encoding is versioned and implemented in the codec layer
// (see pkg/models/stable/ir/codec/json).
//
// Value is a sum type; concrete variants include Literal, Constructor, Tuple, etc.
// The interface is intentionally small: callers typically pattern-match using a
// type switch.
//
// All variants use unexported fields and provide accessors to preserve
// immutability/value semantics.
//
// See also: Morphir.IR.Value in finos/morphir-elm.
type Value[TA any, VA any] interface {
	isValue()
	Attributes() VA
}

// LiteralValue corresponds to: Literal va Literal
//
// Represents a literal value like 13, True or "foo".
type LiteralValue[TA any, VA any] struct {
	attributes VA
	literal    Literal
}

func NewLiteralValue[TA any, VA any](attributes VA, literal Literal) Value[TA, VA] {
	return LiteralValue[TA, VA]{attributes: attributes, literal: literal}
}

func (LiteralValue[TA, VA]) isValue() {}

func (v LiteralValue[TA, VA]) Attributes() VA { return v.attributes }

func (v LiteralValue[TA, VA]) Literal() Literal { return v.literal }

// ConstructorValue corresponds to: Constructor va FQName
//
// Reference to a custom type constructor name.
type ConstructorValue[TA any, VA any] struct {
	attributes VA
	name       FQName
}

func NewConstructorValue[TA any, VA any](attributes VA, name FQName) Value[TA, VA] {
	return ConstructorValue[TA, VA]{attributes: attributes, name: name}
}

func (ConstructorValue[TA, VA]) isValue() {}

func (v ConstructorValue[TA, VA]) Attributes() VA { return v.attributes }

func (v ConstructorValue[TA, VA]) ConstructorName() FQName { return v.name }

// TupleValue corresponds to: Tuple va (List (Value ta va))
//
// Represents a tuple value.
type TupleValue[TA any, VA any] struct {
	attributes VA
	elements   []Value[TA, VA]
}

func NewTupleValue[TA any, VA any](attributes VA, elements []Value[TA, VA]) Value[TA, VA] {
	var copied []Value[TA, VA]
	if len(elements) > 0 {
		copied = make([]Value[TA, VA], len(elements))
		copy(copied, elements)
	}
	return TupleValue[TA, VA]{attributes: attributes, elements: copied}
}

func (TupleValue[TA, VA]) isValue() {}

func (v TupleValue[TA, VA]) Attributes() VA { return v.attributes }

func (v TupleValue[TA, VA]) Elements() []Value[TA, VA] {
	if len(v.elements) == 0 {
		return nil
	}
	copied := make([]Value[TA, VA], len(v.elements))
	copy(copied, v.elements)
	return copied
}

// ListValue corresponds to: List va (List (Value ta va))
//
// Represents a list of values.
type ListValue[TA any, VA any] struct {
	attributes VA
	items      []Value[TA, VA]
}

func NewListValue[TA any, VA any](attributes VA, items []Value[TA, VA]) Value[TA, VA] {
	var copied []Value[TA, VA]
	if len(items) > 0 {
		copied = make([]Value[TA, VA], len(items))
		copy(copied, items)
	}
	return ListValue[TA, VA]{attributes: attributes, items: copied}
}

func (ListValue[TA, VA]) isValue() {}

func (v ListValue[TA, VA]) Attributes() VA { return v.attributes }

func (v ListValue[TA, VA]) Items() []Value[TA, VA] {
	if len(v.items) == 0 {
		return nil
	}
	copied := make([]Value[TA, VA], len(v.items))
	copy(copied, v.items)
	return copied
}

// RecordValue corresponds to: Record va (Dict Name (Value ta va))
//
// Represents a record value.
type RecordValue[TA any, VA any] struct {
	attributes VA
	fields     []RecordField[TA, VA]
}

// RecordField represents a single field in a record value.
type RecordField[TA any, VA any] struct {
	name  Name
	value Value[TA, VA]
}

// RecordFieldFromParts constructs a record field.
func RecordFieldFromParts[TA any, VA any](name Name, value Value[TA, VA]) RecordField[TA, VA] {
	return RecordField[TA, VA]{name: name, value: value}
}

func (f RecordField[TA, VA]) Name() Name { return f.name }

func (f RecordField[TA, VA]) Value() Value[TA, VA] { return f.value }

func NewRecordValue[TA any, VA any](attributes VA, fields []RecordField[TA, VA]) Value[TA, VA] {
	var copied []RecordField[TA, VA]
	if len(fields) > 0 {
		copied = make([]RecordField[TA, VA], len(fields))
		copy(copied, fields)
	}
	return RecordValue[TA, VA]{attributes: attributes, fields: copied}
}

func (RecordValue[TA, VA]) isValue() {}

func (v RecordValue[TA, VA]) Attributes() VA { return v.attributes }

func (v RecordValue[TA, VA]) Fields() []RecordField[TA, VA] {
	if len(v.fields) == 0 {
		return nil
	}
	copied := make([]RecordField[TA, VA], len(v.fields))
	copy(copied, v.fields)
	return copied
}

// VariableValue corresponds to: Variable va Name
//
// Reference to a variable in scope.
type VariableValue[TA any, VA any] struct {
	attributes VA
	name       Name
}

func NewVariableValue[TA any, VA any](attributes VA, name Name) Value[TA, VA] {
	return VariableValue[TA, VA]{attributes: attributes, name: name}
}

func (VariableValue[TA, VA]) isValue() {}

func (v VariableValue[TA, VA]) Attributes() VA { return v.attributes }

func (v VariableValue[TA, VA]) VariableName() Name { return v.name }

// ReferenceValue corresponds to: Reference va FQName
//
// Reference to another value within or outside the module.
type ReferenceValue[TA any, VA any] struct {
	attributes VA
	name       FQName
}

func NewReferenceValue[TA any, VA any](attributes VA, name FQName) Value[TA, VA] {
	return ReferenceValue[TA, VA]{attributes: attributes, name: name}
}

func (ReferenceValue[TA, VA]) isValue() {}

func (v ReferenceValue[TA, VA]) Attributes() VA { return v.attributes }

func (v ReferenceValue[TA, VA]) ReferenceName() FQName { return v.name }

// FieldValue corresponds to: Field va (Value ta va) Name
//
// Represents accessing a field on a record together with the target expression.
type FieldValue[TA any, VA any] struct {
	attributes VA
	subject    Value[TA, VA]
	fieldName  Name
}

func NewFieldValue[TA any, VA any](attributes VA, subject Value[TA, VA], fieldName Name) Value[TA, VA] {
	return FieldValue[TA, VA]{attributes: attributes, subject: subject, fieldName: fieldName}
}

func (FieldValue[TA, VA]) isValue() {}

func (v FieldValue[TA, VA]) Attributes() VA { return v.attributes }

func (v FieldValue[TA, VA]) Subject() Value[TA, VA] { return v.subject }

func (v FieldValue[TA, VA]) FieldName() Name { return v.fieldName }

// FieldFunctionValue corresponds to: FieldFunction va Name
//
// Represents accessing a field on a record without the target expression.
// This is a shortcut to refer to the function that extracts the field from the input.
type FieldFunctionValue[TA any, VA any] struct {
	attributes VA
	fieldName  Name
}

func NewFieldFunctionValue[TA any, VA any](attributes VA, fieldName Name) Value[TA, VA] {
	return FieldFunctionValue[TA, VA]{attributes: attributes, fieldName: fieldName}
}

func (FieldFunctionValue[TA, VA]) isValue() {}

func (v FieldFunctionValue[TA, VA]) Attributes() VA { return v.attributes }

func (v FieldFunctionValue[TA, VA]) FieldName() Name { return v.fieldName }

// ApplyValue corresponds to: Apply va (Value ta va) (Value ta va)
//
// Represents a function application.
type ApplyValue[TA any, VA any] struct {
	attributes VA
	function   Value[TA, VA]
	argument   Value[TA, VA]
}

func NewApplyValue[TA any, VA any](attributes VA, function Value[TA, VA], argument Value[TA, VA]) Value[TA, VA] {
	return ApplyValue[TA, VA]{attributes: attributes, function: function, argument: argument}
}

func (ApplyValue[TA, VA]) isValue() {}

func (v ApplyValue[TA, VA]) Attributes() VA { return v.attributes }

func (v ApplyValue[TA, VA]) Function() Value[TA, VA] { return v.function }

func (v ApplyValue[TA, VA]) Argument() Value[TA, VA] { return v.argument }

// LambdaValue corresponds to: Lambda va (Pattern va) (Value ta va)
//
// Represents a lambda abstraction.
type LambdaValue[TA any, VA any] struct {
	attributes      VA
	argumentPattern Pattern[VA]
	body            Value[TA, VA]
}

func NewLambdaValue[TA any, VA any](attributes VA, argumentPattern Pattern[VA], body Value[TA, VA]) Value[TA, VA] {
	return LambdaValue[TA, VA]{attributes: attributes, argumentPattern: argumentPattern, body: body}
}

func (LambdaValue[TA, VA]) isValue() {}

func (v LambdaValue[TA, VA]) Attributes() VA { return v.attributes }

func (v LambdaValue[TA, VA]) ArgumentPattern() Pattern[VA] { return v.argumentPattern }

func (v LambdaValue[TA, VA]) Body() Value[TA, VA] { return v.body }

// ValueDefinition represents a value or function definition.
// In Elm: { inputTypes : List ( Name, va, Type ta ), outputType : Type ta, body : Value ta va }
type ValueDefinition[TA any, VA any] struct {
	inputTypes []ValueDefinitionInput[TA, VA]
	outputType Type[TA]
	body       Value[TA, VA]
}

// ValueDefinitionInput represents an input parameter to a value definition.
type ValueDefinitionInput[TA any, VA any] struct {
	name       Name
	attributes VA
	tpe        Type[TA]
}

func ValueDefinitionInputFromParts[TA any, VA any](name Name, attributes VA, tpe Type[TA]) ValueDefinitionInput[TA, VA] {
	return ValueDefinitionInput[TA, VA]{name: name, attributes: attributes, tpe: tpe}
}

func (i ValueDefinitionInput[TA, VA]) Name() Name     { return i.name }
func (i ValueDefinitionInput[TA, VA]) Attributes() VA { return i.attributes }
func (i ValueDefinitionInput[TA, VA]) Type() Type[TA] { return i.tpe }

func NewValueDefinition[TA any, VA any](inputTypes []ValueDefinitionInput[TA, VA], outputType Type[TA], body Value[TA, VA]) ValueDefinition[TA, VA] {
	var copied []ValueDefinitionInput[TA, VA]
	if len(inputTypes) > 0 {
		copied = make([]ValueDefinitionInput[TA, VA], len(inputTypes))
		copy(copied, inputTypes)
	}
	return ValueDefinition[TA, VA]{inputTypes: copied, outputType: outputType, body: body}
}

func (d ValueDefinition[TA, VA]) InputTypes() []ValueDefinitionInput[TA, VA] {
	if len(d.inputTypes) == 0 {
		return nil
	}
	copied := make([]ValueDefinitionInput[TA, VA], len(d.inputTypes))
	copy(copied, d.inputTypes)
	return copied
}

func (d ValueDefinition[TA, VA]) OutputType() Type[TA] { return d.outputType }
func (d ValueDefinition[TA, VA]) Body() Value[TA, VA]  { return d.body }

// LetDefinitionValue corresponds to: LetDefinition va Name (Definition ta va) (Value ta va)
//
// Represents a single let binding.
type LetDefinitionValue[TA any, VA any] struct {
	attributes VA
	valueName  Name
	definition ValueDefinition[TA, VA]
	inValue    Value[TA, VA]
}

func NewLetDefinitionValue[TA any, VA any](attributes VA, valueName Name, definition ValueDefinition[TA, VA], inValue Value[TA, VA]) Value[TA, VA] {
	return LetDefinitionValue[TA, VA]{attributes: attributes, valueName: valueName, definition: definition, inValue: inValue}
}

func (LetDefinitionValue[TA, VA]) isValue() {}

func (v LetDefinitionValue[TA, VA]) Attributes() VA { return v.attributes }

func (v LetDefinitionValue[TA, VA]) ValueName() Name { return v.valueName }

func (v LetDefinitionValue[TA, VA]) Definition() ValueDefinition[TA, VA] { return v.definition }

func (v LetDefinitionValue[TA, VA]) InValue() Value[TA, VA] { return v.inValue }

// LetRecursionValue corresponds to: LetRecursion va (Dict Name (Definition ta va)) (Value ta va)
//
// Special let binding that allows mutual recursion between the bindings.
type LetRecursionValue[TA any, VA any] struct {
	attributes  VA
	definitions []NamedValueDefinition[TA, VA]
	inValue     Value[TA, VA]
}

// NamedValueDefinition pairs a name with a definition.
type NamedValueDefinition[TA any, VA any] struct {
	name       Name
	definition ValueDefinition[TA, VA]
}

func NamedValueDefinitionFromParts[TA any, VA any](name Name, definition ValueDefinition[TA, VA]) NamedValueDefinition[TA, VA] {
	return NamedValueDefinition[TA, VA]{name: name, definition: definition}
}

func (n NamedValueDefinition[TA, VA]) Name() Name                          { return n.name }
func (n NamedValueDefinition[TA, VA]) Definition() ValueDefinition[TA, VA] { return n.definition }

func NewLetRecursionValue[TA any, VA any](attributes VA, definitions []NamedValueDefinition[TA, VA], inValue Value[TA, VA]) Value[TA, VA] {
	var copied []NamedValueDefinition[TA, VA]
	if len(definitions) > 0 {
		copied = make([]NamedValueDefinition[TA, VA], len(definitions))
		copy(copied, definitions)
	}
	return LetRecursionValue[TA, VA]{attributes: attributes, definitions: copied, inValue: inValue}
}

func (LetRecursionValue[TA, VA]) isValue() {}

func (v LetRecursionValue[TA, VA]) Attributes() VA { return v.attributes }

func (v LetRecursionValue[TA, VA]) Definitions() []NamedValueDefinition[TA, VA] {
	if len(v.definitions) == 0 {
		return nil
	}
	copied := make([]NamedValueDefinition[TA, VA], len(v.definitions))
	copy(copied, v.definitions)
	return copied
}

func (v LetRecursionValue[TA, VA]) InValue() Value[TA, VA] { return v.inValue }

// DestructureValue corresponds to: Destructure va (Pattern va) (Value ta va) (Value ta va)
//
// Applies a pattern match to the first expression and passes any extracted variables to the second expression.
type DestructureValue[TA any, VA any] struct {
	attributes      VA
	pattern         Pattern[VA]
	valueToDestruct Value[TA, VA]
	inValue         Value[TA, VA]
}

func NewDestructureValue[TA any, VA any](attributes VA, pattern Pattern[VA], valueToDestruct Value[TA, VA], inValue Value[TA, VA]) Value[TA, VA] {
	return DestructureValue[TA, VA]{attributes: attributes, pattern: pattern, valueToDestruct: valueToDestruct, inValue: inValue}
}

func (DestructureValue[TA, VA]) isValue() {}

func (v DestructureValue[TA, VA]) Attributes() VA { return v.attributes }

func (v DestructureValue[TA, VA]) Pattern() Pattern[VA] { return v.pattern }

func (v DestructureValue[TA, VA]) ValueToDestruct() Value[TA, VA] { return v.valueToDestruct }

func (v DestructureValue[TA, VA]) InValue() Value[TA, VA] { return v.inValue }

// IfThenElseValue corresponds to: IfThenElse va (Value ta va) (Value ta va) (Value ta va)
//
// Represents a simple if/then/else expression.
type IfThenElseValue[TA any, VA any] struct {
	attributes VA
	condition  Value[TA, VA]
	thenBranch Value[TA, VA]
	elseBranch Value[TA, VA]
}

func NewIfThenElseValue[TA any, VA any](attributes VA, condition Value[TA, VA], thenBranch Value[TA, VA], elseBranch Value[TA, VA]) Value[TA, VA] {
	return IfThenElseValue[TA, VA]{attributes: attributes, condition: condition, thenBranch: thenBranch, elseBranch: elseBranch}
}

func (IfThenElseValue[TA, VA]) isValue() {}

func (v IfThenElseValue[TA, VA]) Attributes() VA { return v.attributes }

func (v IfThenElseValue[TA, VA]) Condition() Value[TA, VA] { return v.condition }

func (v IfThenElseValue[TA, VA]) ThenBranch() Value[TA, VA] { return v.thenBranch }

func (v IfThenElseValue[TA, VA]) ElseBranch() Value[TA, VA] { return v.elseBranch }

// PatternMatchValue corresponds to: PatternMatch va (Value ta va) (List ( Pattern va, Value ta va ))
//
// Represents a pattern-match.
type PatternMatchValue[TA any, VA any] struct {
	attributes VA
	subject    Value[TA, VA]
	cases      []PatternMatchCase[TA, VA]
}

// PatternMatchCase represents a single case in a pattern match.
type PatternMatchCase[TA any, VA any] struct {
	pattern Pattern[VA]
	body    Value[TA, VA]
}

func PatternMatchCaseFromParts[TA any, VA any](pattern Pattern[VA], body Value[TA, VA]) PatternMatchCase[TA, VA] {
	return PatternMatchCase[TA, VA]{pattern: pattern, body: body}
}

func (c PatternMatchCase[TA, VA]) Pattern() Pattern[VA] { return c.pattern }
func (c PatternMatchCase[TA, VA]) Body() Value[TA, VA]  { return c.body }

func NewPatternMatchValue[TA any, VA any](attributes VA, subject Value[TA, VA], cases []PatternMatchCase[TA, VA]) Value[TA, VA] {
	var copied []PatternMatchCase[TA, VA]
	if len(cases) > 0 {
		copied = make([]PatternMatchCase[TA, VA], len(cases))
		copy(copied, cases)
	}
	return PatternMatchValue[TA, VA]{attributes: attributes, subject: subject, cases: copied}
}

func (PatternMatchValue[TA, VA]) isValue() {}

func (v PatternMatchValue[TA, VA]) Attributes() VA { return v.attributes }

func (v PatternMatchValue[TA, VA]) Subject() Value[TA, VA] { return v.subject }

func (v PatternMatchValue[TA, VA]) Cases() []PatternMatchCase[TA, VA] {
	if len(v.cases) == 0 {
		return nil
	}
	copied := make([]PatternMatchCase[TA, VA], len(v.cases))
	copy(copied, v.cases)
	return copied
}

// UpdateRecordValue corresponds to: UpdateRecord va (Value ta va) (Dict Name (Value ta va))
//
// Expression to update one or more fields of a record value.
type UpdateRecordValue[TA any, VA any] struct {
	attributes     VA
	valueToUpdate  Value[TA, VA]
	fieldsToUpdate []RecordField[TA, VA]
}

func NewUpdateRecordValue[TA any, VA any](attributes VA, valueToUpdate Value[TA, VA], fieldsToUpdate []RecordField[TA, VA]) Value[TA, VA] {
	var copied []RecordField[TA, VA]
	if len(fieldsToUpdate) > 0 {
		copied = make([]RecordField[TA, VA], len(fieldsToUpdate))
		copy(copied, fieldsToUpdate)
	}
	return UpdateRecordValue[TA, VA]{attributes: attributes, valueToUpdate: valueToUpdate, fieldsToUpdate: copied}
}

func (UpdateRecordValue[TA, VA]) isValue() {}

func (v UpdateRecordValue[TA, VA]) Attributes() VA { return v.attributes }

func (v UpdateRecordValue[TA, VA]) ValueToUpdate() Value[TA, VA] { return v.valueToUpdate }

func (v UpdateRecordValue[TA, VA]) FieldsToUpdate() []RecordField[TA, VA] {
	if len(v.fieldsToUpdate) == 0 {
		return nil
	}
	copied := make([]RecordField[TA, VA], len(v.fieldsToUpdate))
	copy(copied, v.fieldsToUpdate)
	return copied
}

// UnitValue corresponds to: Unit va
//
// Represents the single value in the Unit type.
type UnitValue[TA any, VA any] struct {
	attributes VA
}

func NewUnitValue[TA any, VA any](attributes VA) Value[TA, VA] {
	return UnitValue[TA, VA]{attributes: attributes}
}

func (UnitValue[TA, VA]) isValue() {}

func (v UnitValue[TA, VA]) Attributes() VA { return v.attributes }

// EqualValue performs structural equality between two values using the provided
// attribute equality functions.
func EqualValue[TA any, VA any](
	eqTypeAttributes func(TA, TA) bool,
	eqValueAttributes func(VA, VA) bool,
	left Value[TA, VA],
	right Value[TA, VA],
) bool {
	if left == nil || right == nil {
		return left == nil && right == nil
	}
	return equalValueConcrete(eqTypeAttributes, eqValueAttributes, left, right)
}

func equalValueConcrete[TA any, VA any](
	eqTypeAttributes func(TA, TA) bool,
	eqValueAttributes func(VA, VA) bool,
	left Value[TA, VA],
	right Value[TA, VA],
) bool {
	switch l := left.(type) {
	case LiteralValue[TA, VA]:
		r, ok := right.(LiteralValue[TA, VA])
		return ok && eqValueAttributes(l.attributes, r.attributes) && EqualLiteral(l.literal, r.literal)
	case ConstructorValue[TA, VA]:
		r, ok := right.(ConstructorValue[TA, VA])
		return ok && eqValueAttributes(l.attributes, r.attributes) && l.name.Equal(r.name)
	case TupleValue[TA, VA]:
		r, ok := right.(TupleValue[TA, VA])
		return ok && equalTupleValue(eqTypeAttributes, eqValueAttributes, l, r)
	case ListValue[TA, VA]:
		r, ok := right.(ListValue[TA, VA])
		return ok && equalListValue(eqTypeAttributes, eqValueAttributes, l, r)
	case RecordValue[TA, VA]:
		r, ok := right.(RecordValue[TA, VA])
		return ok && equalRecordValue(eqTypeAttributes, eqValueAttributes, l, r)
	case VariableValue[TA, VA]:
		r, ok := right.(VariableValue[TA, VA])
		return ok && eqValueAttributes(l.attributes, r.attributes) && l.name.Equal(r.name)
	case ReferenceValue[TA, VA]:
		r, ok := right.(ReferenceValue[TA, VA])
		return ok && eqValueAttributes(l.attributes, r.attributes) && l.name.Equal(r.name)
	case FieldValue[TA, VA]:
		r, ok := right.(FieldValue[TA, VA])
		return ok && equalFieldValue(eqTypeAttributes, eqValueAttributes, l, r)
	case FieldFunctionValue[TA, VA]:
		r, ok := right.(FieldFunctionValue[TA, VA])
		return ok && eqValueAttributes(l.attributes, r.attributes) && l.fieldName.Equal(r.fieldName)
	case ApplyValue[TA, VA]:
		r, ok := right.(ApplyValue[TA, VA])
		return ok && equalApplyValue(eqTypeAttributes, eqValueAttributes, l, r)
	case LambdaValue[TA, VA]:
		r, ok := right.(LambdaValue[TA, VA])
		return ok && equalLambdaValue(eqTypeAttributes, eqValueAttributes, l, r)
	case LetDefinitionValue[TA, VA]:
		r, ok := right.(LetDefinitionValue[TA, VA])
		return ok && equalLetDefinitionValue(eqTypeAttributes, eqValueAttributes, l, r)
	case LetRecursionValue[TA, VA]:
		r, ok := right.(LetRecursionValue[TA, VA])
		return ok && equalLetRecursionValue(eqTypeAttributes, eqValueAttributes, l, r)
	case DestructureValue[TA, VA]:
		r, ok := right.(DestructureValue[TA, VA])
		return ok && equalDestructureValue(eqTypeAttributes, eqValueAttributes, l, r)
	case IfThenElseValue[TA, VA]:
		r, ok := right.(IfThenElseValue[TA, VA])
		return ok && equalIfThenElseValue(eqTypeAttributes, eqValueAttributes, l, r)
	case PatternMatchValue[TA, VA]:
		r, ok := right.(PatternMatchValue[TA, VA])
		return ok && equalPatternMatchValue(eqTypeAttributes, eqValueAttributes, l, r)
	case UpdateRecordValue[TA, VA]:
		r, ok := right.(UpdateRecordValue[TA, VA])
		return ok && equalUpdateRecordValue(eqTypeAttributes, eqValueAttributes, l, r)
	case UnitValue[TA, VA]:
		r, ok := right.(UnitValue[TA, VA])
		return ok && eqValueAttributes(l.attributes, r.attributes)
	default:
		return false
	}
}

func equalTupleValue[TA any, VA any](eqTA func(TA, TA) bool, eqVA func(VA, VA) bool, l TupleValue[TA, VA], r TupleValue[TA, VA]) bool {
	if !eqVA(l.attributes, r.attributes) {
		return false
	}
	return equalValueSlice(eqTA, eqVA, l.elements, r.elements)
}

func equalListValue[TA any, VA any](eqTA func(TA, TA) bool, eqVA func(VA, VA) bool, l ListValue[TA, VA], r ListValue[TA, VA]) bool {
	if !eqVA(l.attributes, r.attributes) {
		return false
	}
	return equalValueSlice(eqTA, eqVA, l.items, r.items)
}

func equalRecordValue[TA any, VA any](eqTA func(TA, TA) bool, eqVA func(VA, VA) bool, l RecordValue[TA, VA], r RecordValue[TA, VA]) bool {
	if !eqVA(l.attributes, r.attributes) {
		return false
	}
	if len(l.fields) != len(r.fields) {
		return false
	}
	for i := range l.fields {
		if !l.fields[i].name.Equal(r.fields[i].name) {
			return false
		}
		if !EqualValue(eqTA, eqVA, l.fields[i].value, r.fields[i].value) {
			return false
		}
	}
	return true
}

func equalFieldValue[TA any, VA any](eqTA func(TA, TA) bool, eqVA func(VA, VA) bool, l FieldValue[TA, VA], r FieldValue[TA, VA]) bool {
	if !eqVA(l.attributes, r.attributes) {
		return false
	}
	if !l.fieldName.Equal(r.fieldName) {
		return false
	}
	return EqualValue(eqTA, eqVA, l.subject, r.subject)
}

func equalApplyValue[TA any, VA any](eqTA func(TA, TA) bool, eqVA func(VA, VA) bool, l ApplyValue[TA, VA], r ApplyValue[TA, VA]) bool {
	if !eqVA(l.attributes, r.attributes) {
		return false
	}
	if !EqualValue(eqTA, eqVA, l.function, r.function) {
		return false
	}
	return EqualValue(eqTA, eqVA, l.argument, r.argument)
}

func equalLambdaValue[TA any, VA any](eqTA func(TA, TA) bool, eqVA func(VA, VA) bool, l LambdaValue[TA, VA], r LambdaValue[TA, VA]) bool {
	if !eqVA(l.attributes, r.attributes) {
		return false
	}
	if !EqualPattern(eqVA, l.argumentPattern, r.argumentPattern) {
		return false
	}
	return EqualValue(eqTA, eqVA, l.body, r.body)
}

func equalLetDefinitionValue[TA any, VA any](eqTA func(TA, TA) bool, eqVA func(VA, VA) bool, l LetDefinitionValue[TA, VA], r LetDefinitionValue[TA, VA]) bool {
	if !eqVA(l.attributes, r.attributes) {
		return false
	}
	if !l.valueName.Equal(r.valueName) {
		return false
	}
	if !equalValueDefinition(eqTA, eqVA, l.definition, r.definition) {
		return false
	}
	return EqualValue(eqTA, eqVA, l.inValue, r.inValue)
}

func equalLetRecursionValue[TA any, VA any](eqTA func(TA, TA) bool, eqVA func(VA, VA) bool, l LetRecursionValue[TA, VA], r LetRecursionValue[TA, VA]) bool {
	if !eqVA(l.attributes, r.attributes) {
		return false
	}
	if len(l.definitions) != len(r.definitions) {
		return false
	}
	for i := range l.definitions {
		if !l.definitions[i].name.Equal(r.definitions[i].name) {
			return false
		}
		if !equalValueDefinition(eqTA, eqVA, l.definitions[i].definition, r.definitions[i].definition) {
			return false
		}
	}
	return EqualValue(eqTA, eqVA, l.inValue, r.inValue)
}

func equalDestructureValue[TA any, VA any](eqTA func(TA, TA) bool, eqVA func(VA, VA) bool, l DestructureValue[TA, VA], r DestructureValue[TA, VA]) bool {
	if !eqVA(l.attributes, r.attributes) {
		return false
	}
	if !EqualPattern(eqVA, l.pattern, r.pattern) {
		return false
	}
	if !EqualValue(eqTA, eqVA, l.valueToDestruct, r.valueToDestruct) {
		return false
	}
	return EqualValue(eqTA, eqVA, l.inValue, r.inValue)
}

func equalIfThenElseValue[TA any, VA any](eqTA func(TA, TA) bool, eqVA func(VA, VA) bool, l IfThenElseValue[TA, VA], r IfThenElseValue[TA, VA]) bool {
	if !eqVA(l.attributes, r.attributes) {
		return false
	}
	if !EqualValue(eqTA, eqVA, l.condition, r.condition) {
		return false
	}
	if !EqualValue(eqTA, eqVA, l.thenBranch, r.thenBranch) {
		return false
	}
	return EqualValue(eqTA, eqVA, l.elseBranch, r.elseBranch)
}

func equalPatternMatchValue[TA any, VA any](eqTA func(TA, TA) bool, eqVA func(VA, VA) bool, l PatternMatchValue[TA, VA], r PatternMatchValue[TA, VA]) bool {
	if !eqVA(l.attributes, r.attributes) {
		return false
	}
	if !EqualValue(eqTA, eqVA, l.subject, r.subject) {
		return false
	}
	if len(l.cases) != len(r.cases) {
		return false
	}
	for i := range l.cases {
		if !EqualPattern(eqVA, l.cases[i].pattern, r.cases[i].pattern) {
			return false
		}
		if !EqualValue(eqTA, eqVA, l.cases[i].body, r.cases[i].body) {
			return false
		}
	}
	return true
}

func equalUpdateRecordValue[TA any, VA any](eqTA func(TA, TA) bool, eqVA func(VA, VA) bool, l UpdateRecordValue[TA, VA], r UpdateRecordValue[TA, VA]) bool {
	if !eqVA(l.attributes, r.attributes) {
		return false
	}
	if !EqualValue(eqTA, eqVA, l.valueToUpdate, r.valueToUpdate) {
		return false
	}
	if len(l.fieldsToUpdate) != len(r.fieldsToUpdate) {
		return false
	}
	for i := range l.fieldsToUpdate {
		if !l.fieldsToUpdate[i].name.Equal(r.fieldsToUpdate[i].name) {
			return false
		}
		if !EqualValue(eqTA, eqVA, l.fieldsToUpdate[i].value, r.fieldsToUpdate[i].value) {
			return false
		}
	}
	return true
}

func equalValueSlice[TA any, VA any](eqTA func(TA, TA) bool, eqVA func(VA, VA) bool, l []Value[TA, VA], r []Value[TA, VA]) bool {
	if len(l) != len(r) {
		return false
	}
	for i := range l {
		if !EqualValue(eqTA, eqVA, l[i], r[i]) {
			return false
		}
	}
	return true
}

func equalValueDefinition[TA any, VA any](eqTA func(TA, TA) bool, eqVA func(VA, VA) bool, l ValueDefinition[TA, VA], r ValueDefinition[TA, VA]) bool {
	if len(l.inputTypes) != len(r.inputTypes) {
		return false
	}
	for i := range l.inputTypes {
		if !l.inputTypes[i].name.Equal(r.inputTypes[i].name) {
			return false
		}
		if !eqVA(l.inputTypes[i].attributes, r.inputTypes[i].attributes) {
			return false
		}
		if !EqualType(eqTA, l.inputTypes[i].tpe, r.inputTypes[i].tpe) {
			return false
		}
	}
	if !EqualType(eqTA, l.outputType, r.outputType) {
		return false
	}
	return EqualValue(eqTA, eqVA, l.body, r.body)
}

// MapValueAttributes maps both type and value attributes at each node while preserving the
// Value tree structure.
func MapValueAttributes[TA any, VA any, TB any, VB any](
	v Value[TA, VA],
	mapTypeAttributes func(TA) TB,
	mapValueAttributes func(VA) VB,
) (Value[TB, VB], error) {
	if v == nil {
		return nil, fmt.Errorf("ir: Value must not be nil")
	}
	if mapTypeAttributes == nil {
		return nil, fmt.Errorf("ir: mapTypeAttributes must not be nil")
	}
	if mapValueAttributes == nil {
		return nil, fmt.Errorf("ir: mapValueAttributes must not be nil")
	}

	return mapValueAttributesImpl(v, mapTypeAttributes, mapValueAttributes)
}

func mapValueAttributesImpl[TA any, VA any, TB any, VB any](
	v Value[TA, VA],
	mapTA func(TA) TB,
	mapVA func(VA) VB,
) (Value[TB, VB], error) {
	switch val := v.(type) {
	case LiteralValue[TA, VA]:
		return NewLiteralValue[TB, VB](mapVA(val.attributes), val.literal), nil
	case ConstructorValue[TA, VA]:
		return NewConstructorValue[TB, VB](mapVA(val.attributes), val.name), nil
	case TupleValue[TA, VA]:
		return mapTupleValueAttrs(val, mapTA, mapVA)
	case ListValue[TA, VA]:
		return mapListValueAttrs(val, mapTA, mapVA)
	case RecordValue[TA, VA]:
		return mapRecordValueAttrs(val, mapTA, mapVA)
	case VariableValue[TA, VA]:
		return NewVariableValue[TB, VB](mapVA(val.attributes), val.name), nil
	case ReferenceValue[TA, VA]:
		return NewReferenceValue[TB, VB](mapVA(val.attributes), val.name), nil
	case FieldValue[TA, VA]:
		return mapFieldValueAttrs(val, mapTA, mapVA)
	case FieldFunctionValue[TA, VA]:
		return NewFieldFunctionValue[TB, VB](mapVA(val.attributes), val.fieldName), nil
	case ApplyValue[TA, VA]:
		return mapApplyValueAttrs(val, mapTA, mapVA)
	case LambdaValue[TA, VA]:
		return mapLambdaValueAttrs(val, mapTA, mapVA)
	case LetDefinitionValue[TA, VA]:
		return mapLetDefinitionValueAttrs(val, mapTA, mapVA)
	case LetRecursionValue[TA, VA]:
		return mapLetRecursionValueAttrs(val, mapTA, mapVA)
	case DestructureValue[TA, VA]:
		return mapDestructureValueAttrs(val, mapTA, mapVA)
	case IfThenElseValue[TA, VA]:
		return mapIfThenElseValueAttrs(val, mapTA, mapVA)
	case PatternMatchValue[TA, VA]:
		return mapPatternMatchValueAttrs(val, mapTA, mapVA)
	case UpdateRecordValue[TA, VA]:
		return mapUpdateRecordValueAttrs(val, mapTA, mapVA)
	case UnitValue[TA, VA]:
		return NewUnitValue[TB, VB](mapVA(val.attributes)), nil
	default:
		return nil, fmt.Errorf("ir: unsupported Value variant %T", v)
	}
}

func mapTupleValueAttrs[TA any, VA any, TB any, VB any](val TupleValue[TA, VA], mapTA func(TA) TB, mapVA func(VA) VB) (Value[TB, VB], error) {
	elems, err := mapValueSliceAttrs(val.elements, mapTA, mapVA)
	if err != nil {
		return nil, err
	}
	return NewTupleValue[TB, VB](mapVA(val.attributes), elems), nil
}

func mapListValueAttrs[TA any, VA any, TB any, VB any](val ListValue[TA, VA], mapTA func(TA) TB, mapVA func(VA) VB) (Value[TB, VB], error) {
	items, err := mapValueSliceAttrs(val.items, mapTA, mapVA)
	if err != nil {
		return nil, err
	}
	return NewListValue[TB, VB](mapVA(val.attributes), items), nil
}

func mapRecordValueAttrs[TA any, VA any, TB any, VB any](val RecordValue[TA, VA], mapTA func(TA) TB, mapVA func(VA) VB) (Value[TB, VB], error) {
	fields := make([]RecordField[TB, VB], len(val.fields))
	for i, f := range val.fields {
		mapped, err := mapValueAttributesImpl(f.value, mapTA, mapVA)
		if err != nil {
			return nil, err
		}
		fields[i] = RecordFieldFromParts[TB, VB](f.name, mapped)
	}
	return NewRecordValue[TB, VB](mapVA(val.attributes), fields), nil
}

func mapFieldValueAttrs[TA any, VA any, TB any, VB any](val FieldValue[TA, VA], mapTA func(TA) TB, mapVA func(VA) VB) (Value[TB, VB], error) {
	subject, err := mapValueAttributesImpl(val.subject, mapTA, mapVA)
	if err != nil {
		return nil, err
	}
	return NewFieldValue[TB, VB](mapVA(val.attributes), subject, val.fieldName), nil
}

func mapApplyValueAttrs[TA any, VA any, TB any, VB any](val ApplyValue[TA, VA], mapTA func(TA) TB, mapVA func(VA) VB) (Value[TB, VB], error) {
	fn, err := mapValueAttributesImpl(val.function, mapTA, mapVA)
	if err != nil {
		return nil, err
	}
	arg, err := mapValueAttributesImpl(val.argument, mapTA, mapVA)
	if err != nil {
		return nil, err
	}
	return NewApplyValue[TB, VB](mapVA(val.attributes), fn, arg), nil
}

func mapLambdaValueAttrs[TA any, VA any, TB any, VB any](val LambdaValue[TA, VA], mapTA func(TA) TB, mapVA func(VA) VB) (Value[TB, VB], error) {
	pattern, err := MapPatternAttributes[VA, VB](val.argumentPattern, mapVA)
	if err != nil {
		return nil, err
	}
	body, err := mapValueAttributesImpl(val.body, mapTA, mapVA)
	if err != nil {
		return nil, err
	}
	return NewLambdaValue[TB, VB](mapVA(val.attributes), pattern, body), nil
}

func mapLetDefinitionValueAttrs[TA any, VA any, TB any, VB any](val LetDefinitionValue[TA, VA], mapTA func(TA) TB, mapVA func(VA) VB) (Value[TB, VB], error) {
	def, err := mapValueDefinitionAttrs(val.definition, mapTA, mapVA)
	if err != nil {
		return nil, err
	}
	inValue, err := mapValueAttributesImpl(val.inValue, mapTA, mapVA)
	if err != nil {
		return nil, err
	}
	return NewLetDefinitionValue[TB, VB](mapVA(val.attributes), val.valueName, def, inValue), nil
}

func mapLetRecursionValueAttrs[TA any, VA any, TB any, VB any](val LetRecursionValue[TA, VA], mapTA func(TA) TB, mapVA func(VA) VB) (Value[TB, VB], error) {
	defs := make([]NamedValueDefinition[TB, VB], len(val.definitions))
	for i, nd := range val.definitions {
		def, err := mapValueDefinitionAttrs(nd.definition, mapTA, mapVA)
		if err != nil {
			return nil, err
		}
		defs[i] = NamedValueDefinitionFromParts[TB, VB](nd.name, def)
	}
	inValue, err := mapValueAttributesImpl(val.inValue, mapTA, mapVA)
	if err != nil {
		return nil, err
	}
	return NewLetRecursionValue[TB, VB](mapVA(val.attributes), defs, inValue), nil
}

func mapDestructureValueAttrs[TA any, VA any, TB any, VB any](val DestructureValue[TA, VA], mapTA func(TA) TB, mapVA func(VA) VB) (Value[TB, VB], error) {
	pattern, err := MapPatternAttributes[VA, VB](val.pattern, mapVA)
	if err != nil {
		return nil, err
	}
	valueToDestruct, err := mapValueAttributesImpl(val.valueToDestruct, mapTA, mapVA)
	if err != nil {
		return nil, err
	}
	inValue, err := mapValueAttributesImpl(val.inValue, mapTA, mapVA)
	if err != nil {
		return nil, err
	}
	return NewDestructureValue[TB, VB](mapVA(val.attributes), pattern, valueToDestruct, inValue), nil
}

func mapIfThenElseValueAttrs[TA any, VA any, TB any, VB any](val IfThenElseValue[TA, VA], mapTA func(TA) TB, mapVA func(VA) VB) (Value[TB, VB], error) {
	cond, err := mapValueAttributesImpl(val.condition, mapTA, mapVA)
	if err != nil {
		return nil, err
	}
	thenBranch, err := mapValueAttributesImpl(val.thenBranch, mapTA, mapVA)
	if err != nil {
		return nil, err
	}
	elseBranch, err := mapValueAttributesImpl(val.elseBranch, mapTA, mapVA)
	if err != nil {
		return nil, err
	}
	return NewIfThenElseValue[TB, VB](mapVA(val.attributes), cond, thenBranch, elseBranch), nil
}

func mapPatternMatchValueAttrs[TA any, VA any, TB any, VB any](val PatternMatchValue[TA, VA], mapTA func(TA) TB, mapVA func(VA) VB) (Value[TB, VB], error) {
	subject, err := mapValueAttributesImpl(val.subject, mapTA, mapVA)
	if err != nil {
		return nil, err
	}
	cases := make([]PatternMatchCase[TB, VB], len(val.cases))
	for i, c := range val.cases {
		pattern, err := MapPatternAttributes[VA, VB](c.pattern, mapVA)
		if err != nil {
			return nil, err
		}
		body, err := mapValueAttributesImpl(c.body, mapTA, mapVA)
		if err != nil {
			return nil, err
		}
		cases[i] = PatternMatchCaseFromParts[TB, VB](pattern, body)
	}
	return NewPatternMatchValue[TB, VB](mapVA(val.attributes), subject, cases), nil
}

func mapUpdateRecordValueAttrs[TA any, VA any, TB any, VB any](val UpdateRecordValue[TA, VA], mapTA func(TA) TB, mapVA func(VA) VB) (Value[TB, VB], error) {
	valueToUpdate, err := mapValueAttributesImpl(val.valueToUpdate, mapTA, mapVA)
	if err != nil {
		return nil, err
	}
	fields := make([]RecordField[TB, VB], len(val.fieldsToUpdate))
	for i, f := range val.fieldsToUpdate {
		mapped, err := mapValueAttributesImpl(f.value, mapTA, mapVA)
		if err != nil {
			return nil, err
		}
		fields[i] = RecordFieldFromParts[TB, VB](f.name, mapped)
	}
	return NewUpdateRecordValue[TB, VB](mapVA(val.attributes), valueToUpdate, fields), nil
}

func mapValueSliceAttrs[TA any, VA any, TB any, VB any](values []Value[TA, VA], mapTA func(TA) TB, mapVA func(VA) VB) ([]Value[TB, VB], error) {
	if len(values) == 0 {
		return nil, nil
	}
	result := make([]Value[TB, VB], len(values))
	for i, val := range values {
		mapped, err := mapValueAttributesImpl(val, mapTA, mapVA)
		if err != nil {
			return nil, err
		}
		result[i] = mapped
	}
	return result, nil
}

func mapValueDefinitionAttrs[TA any, VA any, TB any, VB any](def ValueDefinition[TA, VA], mapTA func(TA) TB, mapVA func(VA) VB) (ValueDefinition[TB, VB], error) {
	inputs := make([]ValueDefinitionInput[TB, VB], len(def.inputTypes))
	for i, inp := range def.inputTypes {
		// Note: Type attribute mapping requires MapTypeAttributes helper
		// For now, this is a simplification that doesn't exist yet.
		// We'll handle this in the codec layer where we have the actual attribute values.
		inputs[i] = ValueDefinitionInputFromParts[TB, VB](inp.name, mapVA(inp.attributes), nil)
	}
	body, err := mapValueAttributesImpl(def.body, mapTA, mapVA)
	if err != nil {
		return ValueDefinition[TB, VB]{}, err
	}
	return NewValueDefinition[TB, VB](inputs, nil, body), nil
}

// ValueSpecification represents the specification (signature) of a value.
// In Elm: { inputs : List ( Name, Type ta ), output : Type ta }
type ValueSpecification[TA any] struct {
	inputs []ValueSpecificationInput[TA]
	output Type[TA]
}

// ValueSpecificationInput represents an input parameter to a value specification.
type ValueSpecificationInput[TA any] struct {
	name Name
	tpe  Type[TA]
}

// ValueSpecificationInputFromParts constructs a value specification input.
func ValueSpecificationInputFromParts[TA any](name Name, tpe Type[TA]) ValueSpecificationInput[TA] {
	return ValueSpecificationInput[TA]{name: name, tpe: tpe}
}

func (i ValueSpecificationInput[TA]) Name() Name     { return i.name }
func (i ValueSpecificationInput[TA]) Type() Type[TA] { return i.tpe }

// NewValueSpecification creates a new value specification.
func NewValueSpecification[TA any](inputs []ValueSpecificationInput[TA], output Type[TA]) ValueSpecification[TA] {
	var copied []ValueSpecificationInput[TA]
	if len(inputs) > 0 {
		copied = make([]ValueSpecificationInput[TA], len(inputs))
		copy(copied, inputs)
	}
	return ValueSpecification[TA]{inputs: copied, output: output}
}

// Inputs returns the input parameters.
func (s ValueSpecification[TA]) Inputs() []ValueSpecificationInput[TA] {
	if len(s.inputs) == 0 {
		return nil
	}
	copied := make([]ValueSpecificationInput[TA], len(s.inputs))
	copy(copied, s.inputs)
	return copied
}

// Output returns the output type.
func (s ValueSpecification[TA]) Output() Type[TA] { return s.output }

// EqualValueSpecification checks structural equality of two value specifications.
func EqualValueSpecification[TA any](eq func(TA, TA) bool, left ValueSpecification[TA], right ValueSpecification[TA]) bool {
	if len(left.inputs) != len(right.inputs) {
		return false
	}
	for i := range left.inputs {
		if !left.inputs[i].name.Equal(right.inputs[i].name) {
			return false
		}
		if !EqualType(eq, left.inputs[i].tpe, right.inputs[i].tpe) {
			return false
		}
	}
	return EqualType(eq, left.output, right.output)
}
