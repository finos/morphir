package tool

import (
	"github.com/finos/morphir/devkit/go/tool/toolname"
	"os"
)

type WorkingDir string

func GetWorkingDir(toolName toolname.ToolName) (WorkingDir, error) {

	//TODO: Based on the tool name check environment variables to see if an overridden working directory is set.
	_ = toolName.IsEmpty()

	dir, err := os.Getwd()
	if err != nil {
		return "", err
	}
	return WorkingDir(dir), nil
}
