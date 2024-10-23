/*
Copyright © 2024 Morphir Maintainers

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

	http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/
package main

import (
	"github.com/finos/morphir/tooling/morphir"
	"github.com/phuslu/log"
	"log/slog"
)

func main() {
	log.Info().Msg("Starting Morphir CLI")
	morphir.Execute()
}

func init() {
	initLogger()
}

func initLogger() {
	log.DefaultLogger = log.Logger{
		Level:      log.InfoLevel,
		Caller:     1,
		TimeField:  "timestamp",
		TimeFormat: "2006-01-02T15:04:05.000Z0700",
		Writer: &log.ConsoleWriter{
			ColorOutput:    true,
			QuoteString:    true,
			EndWithMessage: true,
		},
	}

	logger := (&log.Logger{
		Level:      log.InfoLevel,
		TimeField:  "date",
		TimeFormat: "2006-01-02T15:04:05.000Z0700",
		Caller:     1,
	}).Slog()

	slog.SetDefault(logger)
}
