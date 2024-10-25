package configmgr

import (
	"errors"
	"github.com/anthdm/hollywood/actor"
	"github.com/finos/morphir/devkit/go/config/configmgr"
	"github.com/finos/morphir/devkit/go/io/morphirfs"
	"github.com/finos/morphir/devkit/go/tool"
	"github.com/hack-pad/hackpadfs"
	"github.com/knadh/koanf/parsers/json"
	"github.com/knadh/koanf/parsers/yaml"
	"github.com/knadh/koanf/providers/file"
	"github.com/knadh/koanf/v2"
	"github.com/life4/genesis/slices"
	"github.com/phuslu/log"
	goOS "os"
	"path"
)

type configMgrActor struct {
	toolConfig *koanf.Koanf
	fs         morphirfs.FS
}

func NewConfigMgr(config Config) actor.Producer {
	return func() actor.Receiver {
		return &configMgrActor{
			toolConfig: koanf.New("."),
			fs:         config.FS,
		}
	}
}

func (c *configMgrActor) Receive(context *actor.Context) {
	switch msg := context.Message().(type) {
	case actor.Initialized:
		log.Info().Msg("ConfigMgrActor initialized")
	case configmgr.LoadHostConfig:
		_ = c.loadHostConfig(msg)
	}
}

func (c *configMgrActor) loadHostConfig(msg configmgr.LoadHostConfig) bool {
	toolCfgFileBase := tool.ConfigFileBaseName(msg.ToolName)
	log.Info().Str("tool_config_file_base", toolCfgFileBase).Msg("Loading host config")
	candidates := []struct {
		name     string
		provider koanf.Provider
		parser   koanf.Parser
	}{
		{"json", file.Provider(toolCfgFileBase + ".json"), json.Parser()},
		{"yaml", file.Provider(toolCfgFileBase + ".yaml"), yaml.Parser()},
	}
	cfgDirs, err := tool.GetUserConfigDirs(msg.ToolName)
	if err != nil {
		log.Error().Err(err).Msg("Failed to get config directories")
		return true
	}
	cfgDirsLeastToMost := slices.Reverse(cfgDirs)
	for _, cfgDir := range cfgDirsLeastToMost {
		for _, candidate := range candidates {
			p := path.Join(string(cfgDir), toolCfgFileBase+"."+candidate.name)
			p, err := c.fs.FromOSPath(p)
			if err != nil {
				log.Warn().Err(err).Str("file", p).Msg("Failed to convert path")
				continue
			}
			log.Info().Str("config_path", p).Msg("Checking config path")

			if _, err := c.fs.Lstat(p); err != nil {
				switch {
				case errors.Is(err, goOS.ErrNotExist):
					log.Warn().Err(err).Str("file", p).Msg("Config file does not exist")
				case errors.Is(err, hackpadfs.ErrPermission):
					log.Warn().Err(err).Str("file", p).Msg("Permission denied for config file")
				default:
					log.Warn().Err(err).Str("file", p).Msgf("Error while checking config file: %+v", err)
				}
			} else {
				log.Info().Str("file", p).Msg("Config file exists")
				if err := c.toolConfig.Load(candidate.provider, candidate.parser); err != nil {
					log.Warn().Err(err).Str("file", p).Msg("Failed to load config")
				} else {
					log.Info().Str("file", p).Msg("Loading config...")
					err = c.toolConfig.Load(candidate.provider, candidate.parser)
					if err != nil {
						log.Warn().Err(err).Str("file", p).Msg("Failed to load config")
						continue
					}

					// Successfully loaded the config
					log.Info().Str("file", p).Msg("Successfully loaded config")
				}
			}
		}
	}
	return false
}
