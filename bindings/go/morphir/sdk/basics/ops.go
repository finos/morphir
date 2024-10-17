package basics

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

func IntegerDivide[T Number](a T) func(T) T {
	return func(b T) T {
		return a / b
	}
}
