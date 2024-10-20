package basics

func Abs[T Number](a T) T {
	if a < 0 {
		return -a
	}
	return a
}

func Add[T Number](a T) func(T) T {
	return func(b T) T {
		return a + b
	}
}

func Subtract[T Number](a T) func(T) T {
	return func(b T) T {
		return a - b
	}
}

func Multiply[T Number](a T) func(T) T {
	return func(b T) T {
		return a * b
	}
}

func Negate[T Number](a T) T {
	return -a
}

func IntegerDivide[T Number](a T) func(T) T {
	return func(b T) T {
		return a / b
	}
}
