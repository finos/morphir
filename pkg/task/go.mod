module github.com/finos/morphir/pkg/task

go 1.25.5

require (
	github.com/finos/morphir/pkg/pipeline v0.3.3
	github.com/finos/morphir/pkg/vfs v0.0.0
	github.com/stretchr/testify v1.11.1
)

require (
	github.com/bmatcuk/doublestar/v4 v4.9.1 // indirect
	github.com/davecgh/go-spew v1.1.1 // indirect
	github.com/pmezard/go-difflib v1.0.0 // indirect
	gopkg.in/yaml.v3 v3.0.1 // indirect
)

replace (
	github.com/finos/morphir/pkg/pipeline => ../pipeline
	github.com/finos/morphir/pkg/vfs => ../vfs
)
