package main

import (
	"github.com/alecthomas/kong"
)

type Globals struct {
	WorkingDir string `short:"C" default:"." help:"Change to directory before doing anything else." type:"path"`
}

type CLI struct {
	Globals

	Fetch FetchCmd `cmd:"" help:"Fetch data."`

	Version struct{} `cmd:"" help:"Show version."`
}

func main() {
	cli := CLI{
		Globals: Globals{
			WorkingDir: ".",
		},
	}
	ctx := kong.Parse(&cli,
		kong.Name("emerald"),
		kong.Description("A command line tool dealing with Elm projects and workspace."),
		kong.UsageOnError())

	err := ctx.Run(&cli.Globals)
	ctx.FatalIfErrorf(err)
}
