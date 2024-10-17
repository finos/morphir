package morphircmd

type Globals struct {
	WorkingDir string `short:"W" default:"." help:"The working directory from which the context of all commands are run" type:"path"`
}
