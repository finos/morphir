package sdk

import (
	ir "github.com/finos/morphir-go/pkg/models/ir"
)

// LocalTimeModuleName returns the module name for Morphir.SDK.LocalTime
func LocalTimeModuleName() ir.ModuleName {
	return ir.PathFromString("LocalTime")
}

// LocalTimeModuleSpec returns the module specification for Morphir.SDK.LocalTime
func LocalTimeModuleSpec() ir.ModuleSpecification[ir.Unit] {
	return ir.NewModuleSpecification(
		localTimeTypes(),
		localTimeValues(),
		nil,
	)
}

// localTimeTypes returns the type specifications for the LocalTime module
func localTimeTypes() []ir.ModuleSpecificationType[ir.Unit] {
	return []ir.ModuleSpecificationType[ir.Unit]{
		// LocalTime type
		ir.ModuleSpecificationTypeFromParts[ir.Unit](
			ir.NameFromString("LocalTime"),
			ir.NewDocumented(
				"Type that represents a time concept.",
				ir.NewOpaqueTypeSpecification[ir.Unit](nil),
			),
		),
	}
}

// localTimeValues returns the value specifications for the LocalTime module
func localTimeValues() []ir.ModuleSpecificationValue[ir.Unit] {
	return []ir.ModuleSpecificationValue[ir.Unit]{
		// Construction
		VSpec("fromMilliseconds", []VSpecInput{
			{Name: "millis", Type: intType()},
		}, LocalTimeType(),
			"Construct a time from milliseconds since midnight."),

		VSpec("fromISO", []VSpecInput{
			{Name: "iso", Type: StringType()},
		}, MaybeType(LocalTimeType()),
			"Parse a time from ISO 8601 format."),

		// Arithmetic - Addition
		VSpec("addSeconds", []VSpecInput{
			{Name: "offset", Type: intType()},
			{Name: "startTime", Type: LocalTimeType()},
		}, LocalTimeType(),
			"Add a number of seconds to a time."),

		VSpec("addMinutes", []VSpecInput{
			{Name: "offset", Type: intType()},
			{Name: "startTime", Type: LocalTimeType()},
		}, LocalTimeType(),
			"Add a number of minutes to a time."),

		VSpec("addHours", []VSpecInput{
			{Name: "offset", Type: intType()},
			{Name: "startTime", Type: LocalTimeType()},
		}, LocalTimeType(),
			"Add a number of hours to a time."),

		// Arithmetic - Difference
		VSpec("diffInSeconds", []VSpecInput{
			{Name: "time1", Type: LocalTimeType()},
			{Name: "time2", Type: LocalTimeType()},
		}, intType(),
			"Calculate the difference between two times in seconds."),

		VSpec("diffInMinutes", []VSpecInput{
			{Name: "time1", Type: LocalTimeType()},
			{Name: "time2", Type: LocalTimeType()},
		}, intType(),
			"Calculate the difference between two times in minutes."),

		VSpec("diffInHours", []VSpecInput{
			{Name: "time1", Type: LocalTimeType()},
			{Name: "time2", Type: LocalTimeType()},
		}, intType(),
			"Calculate the difference between two times in hours."),
	}
}

// LocalTimeType creates a LocalTime type reference
func LocalTimeType() ir.Type[ir.Unit] {
	return ir.NewTypeReference(
		ir.Unit{},
		ToFQName(LocalTimeModuleName(), "LocalTime"),
		nil,
	)
}
