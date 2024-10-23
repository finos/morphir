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
		log.Info().Objects("command", msg).Msg("Loading host config")
	}
}
