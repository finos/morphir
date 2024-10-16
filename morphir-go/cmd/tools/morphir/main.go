package main

import (
	"github.com/alecthomas/kong"
	"github.com/finos/morphir/morphir-go/internal/cli/morphircmd"
	"github.com/finos/morphir/morphir-go/pkg/morphir/host"
	"go.uber.org/zap"
)

type Globals = morphircmd.Globals

type CLI struct {
	Globals

	Restore morphircmd.RestoreCmd `cmd:"" help:"Restore tools, dependencies, extensions, and plugins."`
	Verify  morphircmd.VerifyCmd  `cmd:"" help:"Verify the MorphirIR."`

	Version struct{} `cmd:"" help:"Show version."`
}

func main() {
	logger, e := zap.NewProduction()
	if e != nil {
		//TODO: Handle this differently
		panic(e)
	}
	defer func(logger *zap.Logger) {
		_ = logger.Sync()
	}(logger) // flushes buffer, if any

	cli := CLI{
		Globals: Globals{
			WorkingDir: ".",
		},
	}
	ctx := kong.Parse(&cli,
		kong.Name("morphir"),
		kong.Description("Tooling for working with Morphir models, workspaces, and the Morphir IR."),
		kong.UsageOnError(),
		kong.Bind(*logger),
	)

	err := ctx.Run(&cli.Globals)
	ctx.FatalIfErrorf(err)
}

func createHost() *host.Host {
	return host.New(host.WithOsWorkingDir())
}
