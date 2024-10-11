package config

import (
	"log"

	"github.com/knadh/koanf/parsers/json"
	"github.com/knadh/koanf/parsers/yaml"
	"github.com/knadh/koanf/providers/file"
	"github.com/knadh/koanf/v2"
)

var k = koanf.New(".")

func Init() *koanf.Koanf {
	if err := k.Load(file.Provider("morphir.json"), json.Parser()); err != nil {
		log.Fatalf("error loading config: %v", err)
	}

	k.Load(file.Provider("morphir.yaml"), yaml.Parser())

	return k
}

// Write some comments on 