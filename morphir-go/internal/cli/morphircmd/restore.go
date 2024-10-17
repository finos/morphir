package morphircmd

import (
	"fmt"
	"os"

	"github.com/finos/morphir/morphir-go/internal/host"
)

type RestoreCmd struct{}

func (cmd *RestoreCmd) Run(globals *Globals) error {
	h := host.New()

	h.Run()

	fmt.Println("restoring..")
	// Get the current working directory
	cwd, err := os.Getwd()
	// Handle any errors while getting cwd
	if err != nil {
		fmt.Println("Error getting current working directory:", err)
		return err
	}
	// Print the current working directory
	fmt.Println("Current working directory:", cwd)
	return nil
}
