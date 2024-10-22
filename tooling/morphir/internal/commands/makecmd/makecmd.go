package makecmd

import "context"

func Make(ctx context.Context) error {
	println("Making morphir...")
	println("Context: ", ctx)
	if ctx == nil {
		println("Context is nil")
	} else {
		println("Context is not nil")
	}
	return nil
}
