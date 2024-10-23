package configmgr

import (
	"github.com/finos/morphir/devkit/go/tool"
	"github.com/finos/morphir/devkit/go/tool/toolname"
)

type LoadHostConfig struct {
	ToolName           toolname.ToolName `json:"tool_name"`
	WorkingDir         tool.WorkingDir   `json:"working_dir"`
	WorkspaceDir       *string           `json:"workspace_dir,omitempty"`
	HostConfigFilePath *string           `json:"host_config_file_path,omitempty"`
}

type ValidMessages interface {
	LoadHostConfig
}

type Mailbox[Msg ValidMessages] interface {
	Post(msg Msg)
}
