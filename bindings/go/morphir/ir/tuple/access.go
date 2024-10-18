package tuple

func First[T1 any, T2 any](t Tuple2[T1, T2]) T1 {
	return t._1
}

func Second[T1 any, T2 any](t Tuple2[T1, T2]) T2 {
	return t._2
}

func (t Tuple2[A, B]) First() A {
	return t._1
}

func (t Tuple2[A, B]) Second() B {
	return t._2
}
