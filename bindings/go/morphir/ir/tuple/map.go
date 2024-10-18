package tuple

func MapFirst[T1 any, T2 any, U any](f func(T1) U) func(Tuple2[T1, T2]) Tuple2[U, T2] {
	return func(t Tuple2[T1, T2]) Tuple2[U, T2] {
		return Tuple2[U, T2]{f(t._1), t._2}
	}
}

func MapSecond[T1 any, T2 any, U any](f func(T2) U) func(Tuple2[T1, T2]) Tuple2[T1, U] {
	return func(t Tuple2[T1, T2]) Tuple2[T1, U] {
		return Tuple2[T1, U]{t._1, f(t._2)}
	}
}

func MapBoth[T1 any, T2 any, U any, V any](f func(T1) U) func(func(T2) V) func(Tuple2[T1, T2]) Tuple2[U, V] {
	return func(g func(T2) V) func(Tuple2[T1, T2]) Tuple2[U, V] {
		return func(t Tuple2[T1, T2]) Tuple2[U, V] {
			return Tuple2[U, V]{f(t._1), g(t._2)}
		}
	}
}
