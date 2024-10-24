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
	"context"
	"fmt"
	"github.com/finos/morphir/devkit/go/config/configmgr"
	"github.com/finos/morphir/devkit/go/morphircli/session"
	"github.com/finos/morphir/devkit/go/tool"
	"github.com/finos/morphir/devkit/go/tool/toolname"
	"os"
	"time"

	"github.com/knadh/koanf/v2"
	"github.com/phuslu/log"
	"github.com/spf13/cobra"
)

var (
	k       = koanf.New(".")
	cfgFile = ".morphir.yaml"
)

// rootCmd represents the base command when called without any subcommands
var rootCmd = &cobra.Command{
	Use:   "morphir",
	Short: "Work seamlessly with Morphir models, workspaces, projects, and more from the command line",
	Long: `Work seamlessly with Morphir models, workspaces, projects, and more from the command line.
Morphir provides a set of tools for integrating technologies. Morphir is composed of a library of tools that facilitate the digitisation of business logic into multiple different languages & platforms.
`,
	// Uncomment the following line if your bare application
	// has an action associated with it:
	// Run: func(cmd *cobra.Command, args []string) { },
}

// Execute adds all child commands to the root command and sets flags appropriately.
// This is called by main.main(). It only needs to happen once to the rootCmd.
func Execute() {
	err := rootCmd.Execute()
	if err != nil {
		os.Exit(1)
	}
}

func init() {

	//cobra.OnInitialize(initConfig)
	// Here you will define your flags and configuration settings.
	// Cobra supports persistent flags, which, if defined here,
	// will be global for your application.

	rootCmd.PersistentFlags().StringVar(&cfgFile, "config", "", "config file (default is $HOME/.morphir.yaml)")
	rootCmd.PersistentFlags().Bool("no-server", false, "Do not use the morphir server/daemon to run the command")
	rootCmd.PersistentPreRun = func(cmd *cobra.Command, args []string) {
		noServer, err := cmd.Flags().GetBool("no-server")
		if err != nil {
			log.Warn().Err(err).Msg(`error encountered while attempting to read the "--no-server" flag`)
		}

		currentSession, err := initSession(cmd, noServer)
		if err != nil {
			err = fmt.Errorf("error initializing/starting session: %w", err)
			log.Error().Err(err)
			panic(err)
		}

		// Initialize the configuration used for this command
		initConfig(currentSession)
		// TODO: Add coordination logic
		time.Sleep(10 * time.Second)
	}
}

func initSession(cmd *cobra.Command, noServer bool) (*session.Session, error) {
	log.Info().Msg("Initializing session...")
	var s *session.Session
	if noServer {
		s = session.New(session.UsingInProcessServer())
	} else {
		s = session.New(session.UsingOutOfProcessServer())
	}

	// Add the session to the context
	ctx := cmd.Context()
	ctx = context.WithValue(ctx, "session", s)
	cmd.SetContext(ctx)

	cmd.PersistentPostRun = func(cmd *cobra.Command, args []string) {
		s := cmd.Context().Value("session").(*session.Session)
		err := s.Close()
		if err != nil {
			log.Error().Err(err).Msg("error closing session")
		}
	}

	// Start the session
	err := s.Start(ctx)
	if err != nil {
		return s, fmt.Errorf("error starting session: %w", err)
	}
	return s, nil
}

func initConfig(currentSession *session.Session) {

	workingDir, err := tool.GetWorkingDir(toolname.Morphir)
	if err != nil {
		log.Error().Err(err).Msg("Error getting working directory")
		return
	}

	cmd := configmgr.LoadHostConfig{
		ToolName:   toolname.Morphir,
		WorkingDir: workingDir,
	}

	session.PostToConfigMgr(currentSession, cmd)
}
