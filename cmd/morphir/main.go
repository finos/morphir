package main

import (
	"os"

	"github.com/finos/morphir/cmd/morphir/cmd"
)

func main() {
	if err := cmd.Execute(); err != nil {
		os.Exit(1)
	}
}
