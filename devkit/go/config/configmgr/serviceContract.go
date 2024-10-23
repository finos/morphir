package configmgr

import (
	"github.com/finos/morphir/devkit/go/tool"
	"github.com/finos/morphir/devkit/go/tool/toolname"
)

type ConfigMgr interface {
	LoadHostConfig(hostingTool toolname.ToolName, workingDir tool.WorkingDir, workspaceDir *string, hostConfigFilePath *string) error
}
