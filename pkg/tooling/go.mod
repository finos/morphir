module github.com/finos/morphir-go/pkg/tooling

go 1.25.5

require (
	github.com/BurntSushi/toml v1.6.0
	github.com/bmatcuk/doublestar/v4 v4.9.1
	github.com/finos/morphir-go/pkg/config v0.0.0
)

require (
	github.com/joho/godotenv v1.5.1 // indirect
	github.com/pelletier/go-toml/v2 v2.2.4 // indirect
)

replace github.com/finos/morphir-go/pkg/config => ../config
