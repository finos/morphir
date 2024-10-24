package configmgr

import (
	"github.com/anthdm/hollywood/actor"
	"github.com/finos/morphir/devkit/go/config/configmgr"
	"github.com/finos/morphir/devkit/go/io/morphirfs"
	"github.com/finos/morphir/devkit/go/tool"
	"github.com/finos/morphir/devkit/go/tool/toolname"
	"time"
)

type Service struct {
	engine *actor.Engine
	pid    *actor.PID
}

type Config struct {
	FS morphirfs.FS
}

func New(engine *actor.Engine, config Config) configmgr.ConfigMgr {
	return NewService(engine, config)
}

func NewService(engine *actor.Engine, config Config) *Service {
	pid := engine.Spawn(NewConfigMgr(config), "configMgrActor")
	return &Service{
		engine: engine,
		pid:    pid,
	}
}

// ApplyMsg applies the provided message to the given `Service`.
func ApplyMsg[Msg configmgr.ValidMessages](service Service, msg Msg) {
	service.engine.Send(service.pid, msg)
}

func (s *Service) AsConfigMgr() configmgr.ConfigMgr {
	return s
}

func (s *Service) LoadHostConfig(hostingTool toolname.ToolName, workingDir tool.WorkingDir, workspaceDir *string, hostConfigFilePath *string) error {
	s.send(configmgr.LoadHostConfig{
		ToolName:           hostingTool,
		WorkingDir:         workingDir,
		WorkspaceDir:       workspaceDir,
		HostConfigFilePath: hostConfigFilePath,
	})
	return nil
}

func (s *Service) Stop() {
	s.engine.Stop(s.pid)
}

func (s *Service) send(msg interface{}) {
	s.engine.Send(s.pid, msg)
}

func (s *Service) request(msg interface{}, timeout time.Duration) *actor.Response {
	return s.engine.Request(s.pid, msg, timeout)
}
