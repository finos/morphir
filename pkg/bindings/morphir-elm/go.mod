module github.com/finos/morphir/pkg/bindings/morphir-elm

go 1.25.5

require (
	github.com/finos/morphir/pkg/pipeline v0.4.0-alpha.1
	github.com/finos/morphir/pkg/toolchain v0.0.0-00010101000000-000000000000
	github.com/stretchr/testify v1.11.1
)

require (
	github.com/bmatcuk/doublestar/v4 v4.9.1 // indirect
	github.com/davecgh/go-spew v1.1.1 // indirect
	github.com/finos/morphir/pkg/vfs v0.4.0-alpha.1 // indirect
	github.com/pmezard/go-difflib v1.0.0 // indirect
	gopkg.in/yaml.v3 v3.0.1 // indirect
)

replace github.com/finos/morphir/pkg/toolchain => ../../toolchain
