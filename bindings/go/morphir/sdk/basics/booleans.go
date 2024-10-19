package basics

const True = Bool(true)
const False = Bool(false)

func Not[B ~bool](value B) Bool {
	return Bool(!value)
}

func And[B ~bool](lhs B) func(B) Bool {
	return func(rhs B) Bool {
		return Bool(lhs && rhs)
	}
}

func Or[B ~bool](lhs B) func(B) Bool {
	return func(rhs B) Bool {
		return Bool(lhs || rhs)
	}
}

// Xor returns the exclusive or of two boolean values. It is True if exactly one of the two values is True.
func Xor[B ~bool](lhs B) func(B) Bool {
	return func(rhs B) Bool {
		return Bool(lhs != rhs)
	}
}
