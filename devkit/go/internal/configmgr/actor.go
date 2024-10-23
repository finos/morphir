package configmgr

import (
	"github.com/anthdm/hollywood/actor"
	"github.com/finos/morphir/devkit/go/config/configmgr"
	"github.com/knadh/koanf/v2"
	"github.com/phuslu/log"
)

type configMgrActor struct {
	cfg *koanf.Koanf
}

func NewConfigMgr(config Config) actor.Producer {
	return func() actor.Receiver {
		return &configMgrActor{cfg: koanf.New(".")}
	}
}

func (c *configMgrActor) Receive(context *actor.Context) {
	switch msg := context.Message().(type) {
	case actor.Initialized:
		log.Info().Msg("ConfigMgrActor initialized")
	case configmgr.LoadHostConfig:
		//cmd, err := json.Marshal(msg)
		//if err != nil {
		//	workspaceDir := msg.WorkspaceDir
		//	if workspaceDir == nil {
		//		*workspaceDir = ""
		//	}
		//	hostConfigFilePath := msg.HostConfigFilePath
		//	if hostConfigFilePath == nil {
		//		*hostConfigFilePath = ""
		//	}
		//	log.Info().Msg("Uh oh")
		//	log.Info().Fields(log.Fields{
		//		"tool_name":             msg.ToolName,
		//		"working_dir":           msg.WorkingDir,
		//		"workspace_dir":         workspaceDir,
		//		"host_config_file_path": hostConfigFilePath,
		//	}).Msg("Loading host config")
		//	return
		//}
		//
		//log.Info().RawJSON("command", cmd).Msg("Loading host config")

		fields := log.Fields{
			"tool_name":   msg.ToolName,
			"working_dir": msg.WorkingDir,
		}
		//workspaceDir := msg.WorkspaceDir
		//if workspaceDir == nil {
		//	*workspaceDir = ""
		//}
		//hostConfigFilePath := msg.HostConfigFilePath
		//if hostConfigFilePath == nil {
		//	*hostConfigFilePath = ""
		//}
		//log.Info().Msg("Uh oh")
		log.Info().Fields(fields).Msg("Loading host config")
	}
}
