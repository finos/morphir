// Package pipeline provides WIT pipeline adapters for Morphir processing.
//
// This package implements pipeline steps that integrate WIT parsing and emission
// with Morphir's processing infrastructure, following morphir-elm's established
// patterns:
//
//   - make: Frontend compilation (WIT → Morphir IR)
//   - gen: Backend generation (Morphir IR → WIT)
//   - build: Full pipeline (WIT → IR → WIT)
//
// # Architecture
//
// The pipeline steps follow the [pipeline.Step] interface pattern:
//
//	Step[In, Out] with func(Context, In) (Out, StepResult)
//
// Each step produces diagnostics for warnings and errors, supporting both
// lossy transformation warnings and strict validation modes.
//
// # Type Mapping
//
// WIT and Morphir IR have different type systems. The pipeline handles type
// conversion with configurable behavior for lossy mappings:
//
//   - Lossless: bool, string, f64, record, variant, enum, list, option, result, tuple
//   - Lossy: u8/u16/u32/u64, s8/s16/s32/s64, f32, flags, resource
//
// Lossy mappings emit diagnostics which can be configured to be treated as
// errors via the WarningsAsErrors option.
//
// # Usage
//
// Make step (WIT → IR):
//
//	makeStep := pipeline.NewMakeStep()
//	output, result := makeStep.Execute(ctx, MakeInput{
//	    Source: witSource,
//	    Options: MakeOptions{WarningsAsErrors: false},
//	})
//
// Gen step (IR → WIT):
//
//	genStep := pipeline.NewGenStep()
//	output, result := genStep.Execute(ctx, GenInput{
//	    Module: irModule,
//	    OutputPath: vfs.MustVPath("/output.wit"),
//	})
//
// Build step (full pipeline):
//
//	buildStep := pipeline.NewBuildStep()
//	output, result := buildStep.Execute(ctx, BuildInput{
//	    Source: witSource,
//	    OutputPath: vfs.MustVPath("/regenerated.wit"),
//	})
//
// # Diagnostics
//
// The pipeline emits structured diagnostics with codes:
//
//   - WIT001: Integer size/signedness information lost
//   - WIT002: Float precision hint lost (f32 → Float)
//   - WIT003: flags type not supported
//   - WIT004: resource type not supported
//   - WIT005: Round-trip produces semantically different output
//
// # Future Extensibility
//
// The design supports future enhancements:
//
//   - Attributes for preserving WIT-specific metadata in IR
//   - Decorators for Morphir constraints
//   - Per-diagnostic severity configuration
package pipeline
