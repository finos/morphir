module github.com/finos/morphir-go/pkg/tooling

go 1.25.5

require (
	github.com/BurntSushi/toml v1.6.0
	github.com/bmatcuk/doublestar/v4 v4.9.1
	github.com/finos/morphir-go/pkg/config v0.0.0
	github.com/finos/morphir-go/pkg/models v0.0.0
	github.com/santhosh-tekuri/jsonschema/v6 v6.0.2
	sigs.k8s.io/yaml v1.4.0
)

require (
	github.com/joho/godotenv v1.5.1 // indirect
	github.com/pelletier/go-toml/v2 v2.2.4 // indirect
	golang.org/x/text v0.14.0 // indirect
)

replace (
	github.com/finos/morphir-go/pkg/config => ../config
	github.com/finos/morphir-go/pkg/models => ../models
)
