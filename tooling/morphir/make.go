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
	"github.com/knadh/koanf/providers/posflag"
	"github.com/spf13/cobra"
	"go.uber.org/zap"
)

// makeCmd represents the make command
var makeCmd = &cobra.Command{
	Use:   "make",
	Short: "Make a project/workspace",
	Run: func(cmd *cobra.Command, args []string) {

		err := k.Load(posflag.Provider(cmd.Flags(), ".", k), nil)
		if err != nil {
			zap.L().Error("Error loading config", zap.Error(err))
			return
		}
		fmt.Println("make called")
		indent := k.Bool("indent-json")
		fmt.Println("Indent: ", indent)
	},
}

var projectDir string
var output string
var typesOnly bool
var indentJson bool
var includes []string

func init() {
	rootCmd.AddCommand(makeCmd)

	// Here you will define your flags and configuration settings.

	// Cobra supports Persistent Flags which will work for this command
	// and all subcommands, e.g.:
	// makeCmd.PersistentFlags().String("foo", "", "A help for foo")

	// Cobra supports local flags which will only run when this command
	// is called directly, e.g.:
	// makeCmd.Flags().BoolP("toggle", "t", false, "Help message for toggle")
	makeCmd.Flags().StringVarP(&projectDir, "project-dir", "p", ".", "Root directory of the project where the Morphir project file is located")
	err := makeCmd.MarkFlagDirname("project-dir")
	if err != nil {
		zap.L().Error("Error marking flag as directory", zap.Error(err))
		return
	}

	makeCmd.Flags().StringVarP(&output, "output", "o", "morphir.json", "Target file location where the Morphir IR will be saved")
	makeCmd.Flags().BoolVarP(&typesOnly, "types-only", "t", false, "Only include type information in the generated IR, no values")
	makeCmd.Flags().BoolVarP(&indentJson, "indent-json", "i", false, "Use indentation in the generated JSON file")
	makeCmd.Flags().StringSliceVarP(&includes, "include", "I", []string{}, "Include additional Morphir distributions as a dependency.")

}
