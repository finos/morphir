package list

type List[T any] []T

func Nil[T any]() List[T] {
	return []T{}
}
