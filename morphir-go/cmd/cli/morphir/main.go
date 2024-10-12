package main

import (
	"github.com/alecthomas/kong"
	"github.com/finos/morphir/morphir-go/internal/cli/morphircmd"
)

type Globals = morphircmd.Globals

type CLI struct {
	Globals

	Restore morphircmd.RestoreCmd `cmd:"" help:"Restore tools, dependencies, extensions, and plugins."`
	Verify  morphircmd.VerifyCmd  `cmd:"" help:"Verify the MorphirIR."`

	Version struct{} `cmd:"" help:"Show version."`
}

func main() {
	cli := CLI{
		Globals: Globals{
			WorkingDir: ".",
		},
	}
	ctx := kong.Parse(&cli,
		kong.Name("morphir"),
		kong.Description("Tooling for working with Morphir models, workspaces, and the Morphir IR."),
		kong.UsageOnError())

	err := ctx.Run(&cli.Globals)
	ctx.FatalIfErrorf(err)
}
