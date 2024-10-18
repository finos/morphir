package maybe

func Map[T any, U any](mapper func(T) U) func(from Maybe[T]) Maybe[U] {
	return func(from Maybe[T]) Maybe[U] {
		if from.IsEmpty() || mapper == nil {
			return Nothing[U]()
		}
		return New[U](mapper(from.value))
	}
}

func MapUncurried[T any, U any](from Maybe[T], mapper func(T) U) Maybe[U] {
	if from.IsEmpty() || mapper == nil {
		return Nothing[U]()
	}
	return New[U](mapper(from.value))
}

func Map2[A any, B any, Value any](mapper func(A) func(B) Value) func(Maybe[A]) func(Maybe[B]) Maybe[Value] {
	return func(a Maybe[A]) func(Maybe[B]) Maybe[Value] {
		return func(b Maybe[B]) Maybe[Value] {
			if a.IsEmpty() || b.IsEmpty() || mapper == nil {
				return Nothing[Value]()
			}
			return New[Value](mapper(a.value)(b.value))
		}
	}
}
