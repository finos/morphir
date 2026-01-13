package cmd

import (
	_ "embed"
	"encoding/json"
	"fmt"
	"os"
	"runtime"

	"github.com/charmbracelet/glamour"
	"github.com/spf13/cobra"
)

//go:embed CHANGELOG.md
var changelog string

var aboutCmd = &cobra.Command{
	Use:   "about",
	Short: "Display information about Morphir",
	Long:  `Display version, platform information, and changelog for Morphir.`,
	RunE:  runAbout,
}

func init() {
	aboutCmd.Flags().BoolP("json", "j", false, "Output in JSON format")
	aboutCmd.Flags().Bool("changelog", false, "Show full changelog")
	aboutCmd.Flags().Bool("no-color", false, "Disable colored output (also honors NO_COLOR env var)")
}

type AboutInfo struct {
	Version   string `json:"version"`
	GitCommit string `json:"git_commit"`
	BuildDate string `json:"build_date"`
	GoVersion string `json:"go_version"`
	Platform  string `json:"platform"`
	OS        string `json:"os"`
	Arch      string `json:"arch"`
	Changelog string `json:"changelog,omitempty"`
}

func runAbout(cmd *cobra.Command, args []string) error {
	jsonFlag, _ := cmd.Flags().GetBool("json")
	showChangelog, _ := cmd.Flags().GetBool("changelog")
	noColor, _ := cmd.Flags().GetBool("no-color")

	// Check NO_COLOR environment variable (standard: https://no-color.org/)
	if os.Getenv("NO_COLOR") != "" {
		noColor = true
	}

	info := AboutInfo{
		Version:   Version,
		GitCommit: GitCommit,
		BuildDate: BuildDate,
		GoVersion: runtime.Version(),
		Platform:  fmt.Sprintf("%s/%s", runtime.GOOS, runtime.GOARCH),
		OS:        runtime.GOOS,
		Arch:      runtime.GOARCH,
	}

	if showChangelog {
		info.Changelog = changelog
	}

	if jsonFlag {
		encoder := json.NewEncoder(cmd.OutOrStdout())
		encoder.SetIndent("", "  ")
		return encoder.Encode(info)
	}

	// Pretty output (errors intentionally ignored for stdout writes)
	_, _ = fmt.Fprintf(cmd.OutOrStdout(), "Morphir - Functional Data Modeling\n")
	_, _ = fmt.Fprintf(cmd.OutOrStdout(), "═══════════════════════════════════\n\n")
	_, _ = fmt.Fprintf(cmd.OutOrStdout(), "Version:      %s\n", info.Version)
	_, _ = fmt.Fprintf(cmd.OutOrStdout(), "Git Commit:   %s\n", info.GitCommit)
	_, _ = fmt.Fprintf(cmd.OutOrStdout(), "Build Date:   %s\n", info.BuildDate)
	_, _ = fmt.Fprintf(cmd.OutOrStdout(), "Go Version:   %s\n", info.GoVersion)
	_, _ = fmt.Fprintf(cmd.OutOrStdout(), "Platform:     %s\n", info.Platform)
	_, _ = fmt.Fprintf(cmd.OutOrStdout(), "\n")

	if showChangelog {
		_, _ = fmt.Fprintf(cmd.OutOrStdout(), "Changelog\n")
		_, _ = fmt.Fprintf(cmd.OutOrStdout(), "─────────\n\n")

		if noColor {
			// Plain text output without colors
			_, _ = fmt.Fprintf(cmd.OutOrStdout(), "%s\n", changelog)
		} else {
			// Render markdown with glamour (colorful by default)
			rendererOpts := []glamour.TermRendererOption{
				glamour.WithAutoStyle(), // Automatically adapts to dark/light terminal
				glamour.WithWordWrap(100),
			}

			r, err := glamour.NewTermRenderer(rendererOpts...)
			if err != nil {
				// Fallback to plain text if glamour fails
				_, _ = fmt.Fprintf(cmd.OutOrStdout(), "%s\n", changelog)
				return nil
			}

			rendered, err := r.Render(changelog)
			if err != nil {
				_, _ = fmt.Fprintf(cmd.OutOrStdout(), "%s\n", changelog)
				return nil
			}

			_, _ = fmt.Fprint(cmd.OutOrStdout(), rendered)
		}
	} else {
		_, _ = fmt.Fprintf(cmd.OutOrStdout(), "For more information:\n")
		_, _ = fmt.Fprintf(cmd.OutOrStdout(), "  Website:    https://morphir.finos.org\n")
		_, _ = fmt.Fprintf(cmd.OutOrStdout(), "  Repository: https://github.com/finos/morphir\n")
		_, _ = fmt.Fprintf(cmd.OutOrStdout(), "  Changelog:  morphir about --changelog\n")
	}

	return nil
}
