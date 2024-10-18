package tuple

type Tuple2[T1 any, T2 any] struct {
	_1 T1
	_2 T2
}

// Pair create a tuple of two values
func Pair[T1 any, T2 any](first T1) func(T2) Tuple2[T1, T2] {
	return func(second T2) Tuple2[T1, T2] {
		return Tuple2[T1, T2]{first, second}
	}
}

func (t Tuple2[A, B]) AsPair() (A, B) {
	return t._1, t._2
}

func (t Tuple2[A, B]) Swap() Tuple2[B, A] {
	return Tuple2[B, A]{_1: t._2, _2: t._1}
}
