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

// genScalaCmd represents the scala command
var genScalaCmd = &cobra.Command{
	Use:   "scala",
	Short: "Generate Scala code",
	Run: func(cmd *cobra.Command, args []string) {
		fmt.Println("scala called")
	},
}

var scalaVersion string

func init() {
	genCmd.AddCommand(genScalaCmd)

	// Here you will define your flags and configuration settings.

	// Cobra supports Persistent Flags which will work for this command
	// and all subcommands, e.g.:
	// genScalaCmd.PersistentFlags().String("foo", "", "A help for foo")

	// Cobra supports local flags which will only run when this command
	// is called directly, e.g.:
	genScalaCmd.Flags().StringVarP(&scalaVersion, "scala-version", "s", "", "The specific version of Scala to generate code for")
}
