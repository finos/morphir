package domain

// TypeVisitor defines the visitor pattern interface for types.
// This enables extensible type traversal without modifying the type definitions.
// Implementations can choose which types to handle.
//
// Example usage:
//
//	type PrimitiveCollector struct {
//	    primitives []PrimitiveType
//	}
//
//	func (c *PrimitiveCollector) VisitPrimitive(p PrimitiveType) {
//	    c.primitives = append(c.primitives, p)
//	}
type TypeVisitor interface {
	VisitPrimitive(PrimitiveType)
	VisitNamed(NamedType)
	VisitList(ListType)
	VisitOption(OptionType)
	VisitResult(ResultType)
	VisitTuple(TupleType)
	VisitHandle(HandleType)
	VisitFuture(FutureType)
	VisitStream(StreamType)
}

// Accept applies a visitor to a type and all its nested types.
func Accept(t Type, v TypeVisitor) {
	switch typ := t.(type) {
	case PrimitiveType:
		v.VisitPrimitive(typ)
	case NamedType:
		v.VisitNamed(typ)
	case ListType:
		v.VisitList(typ)
		Accept(typ.Element, v)
	case OptionType:
		v.VisitOption(typ)
		Accept(typ.Inner, v)
	case ResultType:
		v.VisitResult(typ)
		if typ.Ok != nil {
			Accept(*typ.Ok, v)
		}
		if typ.Err != nil {
			Accept(*typ.Err, v)
		}
	case TupleType:
		v.VisitTuple(typ)
		for _, elem := range typ.Types {
			Accept(elem, v)
		}
	case HandleType:
		v.VisitHandle(typ)
	case FutureType:
		v.VisitFuture(typ)
		if typ.Inner != nil {
			Accept(*typ.Inner, v)
		}
	case StreamType:
		v.VisitStream(typ)
		if typ.Element != nil {
			Accept(*typ.Element, v)
		}
	}
}

// BaseVisitor provides a default no-op implementation of TypeVisitor.
// Embed this in custom visitors to only override the methods you need.
//
// Example:
//
//	type MyVisitor struct {
//	    BaseVisitor
//	}
//
//	func (v *MyVisitor) VisitPrimitive(p PrimitiveType) {
//	    // custom logic here
//	}
type BaseVisitor struct{}

func (BaseVisitor) VisitPrimitive(PrimitiveType) {}
func (BaseVisitor) VisitNamed(NamedType)         {}
func (BaseVisitor) VisitList(ListType)           {}
func (BaseVisitor) VisitOption(OptionType)       {}
func (BaseVisitor) VisitResult(ResultType)       {}
func (BaseVisitor) VisitTuple(TupleType)         {}
func (BaseVisitor) VisitHandle(HandleType)       {}
func (BaseVisitor) VisitFuture(FutureType)       {}
func (BaseVisitor) VisitStream(StreamType)       {}
