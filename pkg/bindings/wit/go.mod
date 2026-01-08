module github.com/finos/morphir/pkg/bindings/wit

go 1.25.5

require (
	github.com/Masterminds/semver/v3 v3.4.0
	github.com/finos/morphir/pkg/bindings/typemap v0.0.0
	github.com/stretchr/testify v1.11.1
	go.bytecodealliance.org v0.7.0
)

replace github.com/finos/morphir/pkg/bindings/typemap => ../typemap

require (
	github.com/coreos/go-semver v0.3.1 // indirect
	github.com/davecgh/go-spew v1.1.1 // indirect
	github.com/pmezard/go-difflib v1.0.0 // indirect
	github.com/tetratelabs/wazero v1.9.0 // indirect
	gopkg.in/check.v1 v1.0.0-20201130134442-10cb98267c6c // indirect
	gopkg.in/yaml.v3 v3.0.1 // indirect
)
