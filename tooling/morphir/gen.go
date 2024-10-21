/*
Copyright © 2024 FINOS

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

	http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/
package morphir

import (
	"fmt"

	"github.com/spf13/cobra"
)

// genCmd represents the gen command
var genCmd = &cobra.Command{
	Use:   "gen",
	Short: "Perform code generation",
	Long: `Perform code generation for all the configured targets. For example:
	
	morphir gen

Note, you can use the sub commands to generate code for specific targets, and pass target specific options. For example:

	morphir gen scala --scala-version 2.13.3
	morphir gen typescript --typescript-version 4.0.3
	morphir gen typescript --typescript-version 4.0.3 --typescript-output-dir /path/to/output/dir
	morphir gen typescript --typescript-version 4.0.3 --typescript-output-dir /path/to/output/dir --typescript-strict`,
	Run: func(cmd *cobra.Command, args []string) {
		fmt.Printf("gen called with args: %q", args)
		fmt.Println()
		fmt.Printf("targets: %q", targets)
		fmt.Println()
	},
}

var targets []string

func init() {
	rootCmd.AddCommand(genCmd)

	// Here you will define your flags and configuration settings.

	// Cobra supports Persistent Flags which will work for this command
	// and all subcommands, e.g.:
	// genCmd.PersistentFlags().String("foo", "", "A help for foo")

	// Cobra supports local flags which will only run when this command
	// is called directly, e.g.:
	// genCmd.Flags().BoolP("toggle", "t", false, "Help message for toggle")
	genCmd.Flags().StringSliceVarP(&targets, "targets", "t", []string{}, "The targets to generate code for")
}
