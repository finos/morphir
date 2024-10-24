package tool

import (
	"github.com/life4/genesis/slices"
	"os"

	"github.com/finos/morphir/devkit/go/tool/toolname"
	gap "github.com/muesli/go-app-paths"
)

type WorkingDir string

// UserConfigDir represents the tool specific configuration directory for a user.
type UserConfigDir string

func GetWorkingDir(toolName toolname.ToolName) (WorkingDir, error) {

	//TODO: Based on the tool name check environment variables to see if an overridden working directory is set.
	_ = toolName.IsEmpty()

	dir, err := os.Getwd()
	if err != nil {
		return "", err
	}
	return WorkingDir(dir), nil
}

func GetUserConfigDirs(toolName toolname.ToolName) ([]UserConfigDir, error) {
	var scope *gap.Scope

	switch toolName {
	case toolname.Morphir, toolname.Emerald:
		scope = gap.NewVendorScope(gap.User, "finos", string(toolName))
	default:

		scope = gap.NewScope(gap.User, string(toolName))
	}

	configDirs, err := scope.ConfigDirs()
	if err != nil {
		return nil, err
	}

	userConfigDirs := slices.Map(configDirs, func(dir string) UserConfigDir { return UserConfigDir(dir) })
	return userConfigDirs, nil
}
