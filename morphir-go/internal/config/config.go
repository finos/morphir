package config

import (
	"log"

	"github.com/knadh/koanf/parsers/json"
	"github.com/knadh/koanf/parsers/yaml"
	"github.com/knadh/koanf/providers/file"
	"github.com/knadh/koanf/v2"
)

var k = koanf.New(".")

type Db interface {
	All() map[string]interface{}
}

type db struct {
	// add config fields here
	underlying *koanf.Koanf
}

func NewDb() Db {
	if err := k.Load(file.Provider("morphir.json"), json.Parser()); err != nil {
		log.Printf("Loading of morphir.json failed: %v", err)
	}

	if err := k.Load(file.Provider("morphir.yaml"), yaml.Parser()); err != nil {
		log.Printf("Loading of morphir.yaml failed: %v", err)
	}
	return db{underlying: k}
}

func (d db) All() map[string]interface{} {
	return d.underlying.All()
}

// Write some comments on
