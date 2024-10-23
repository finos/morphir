package configmgr

import (
	"github.com/anthdm/hollywood/actor"
	"github.com/finos/morphir/devkit/go/config/configmgr"
	"time"
)

type service struct {
	engine *actor.Engine
	pid    *actor.PID
}

func New(engine *actor.Engine) configmgr.ConfigMgr {
	pid := engine.Spawn(NewConfigMgr(), "configMgrActor")
	mgr := &service{
		engine: engine,
		pid:    pid,
	}
	return mgr
}

func (c *service) LoadHostConfig(workingDir string, workspaceDir *string, hostConfigFilePath *string) error {
	c.send(configmgr.LoadHostConfig{
		WorkingDir:         workingDir,
		WorkspaceDir:       workspaceDir,
		HostConfigFilePath: hostConfigFilePath,
	})
	return nil
}

func (c *service) send(msg interface{}) {
	c.engine.Send(c.pid, msg)
}

func (c *service) request(msg interface{}, timeout time.Duration) *actor.Response {
	return c.engine.Request(c.pid, msg, timeout)
}
