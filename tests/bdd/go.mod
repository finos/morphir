module github.com/finos/morphir-go/tests/bdd

go 1.25.5

require (
	github.com/cucumber/godog v0.15.0
	github.com/finos/morphir-go/pkg/models v0.0.0
)

require (
	github.com/cucumber/gherkin/go/v26 v26.2.0 // indirect
	github.com/cucumber/messages/go/v21 v21.0.1 // indirect
	github.com/gofrs/uuid v4.3.1+incompatible // indirect
	github.com/hashicorp/go-immutable-radix v1.3.1 // indirect
	github.com/hashicorp/go-memdb v1.3.4 // indirect
	github.com/hashicorp/golang-lru v0.5.4 // indirect
	github.com/spf13/pflag v1.0.9 // indirect
)

replace github.com/finos/morphir-go/pkg/models => ../../pkg/models
