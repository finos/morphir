package cmd

import (
	"fmt"

	"github.com/spf13/cobra"
)

var versionCmd = &cobra.Command{
	Use:   "version",
	Short: "Print the version number of morphir",
	Long:  `Print the version number, git commit, and build date of morphir.`,
	Run: func(cmd *cobra.Command, args []string) {
		fmt.Printf("morphir version %s\n", Version)
		fmt.Printf("  commit: %s\n", GitCommit)
		fmt.Printf("  built:  %s\n", BuildDate)
	},
}
