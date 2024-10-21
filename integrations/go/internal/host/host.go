package host

import (
	"fmt"
	"github.com/finos/morphir/integrations/go/internal/config"
)

type ConfigDb config.Db

type Host interface {
	Run()
}

type host struct {
	configDb ConfigDb
}

func New() Host {
	configDb := config.NewDb()
	values := configDb.All()

	// Print all the values in the config
	for k, v := range values {
		fmt.Printf("%s: %v\n", k, v)
	}
	return makeHost(configDb)
}

func makeHost(configDb ConfigDb) Host {
	return &host{configDb: configDb}
}

func (h *host) Run() {
	fmt.Println("Running host")
}
