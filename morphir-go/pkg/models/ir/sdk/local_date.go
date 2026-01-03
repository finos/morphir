package sdk

import (
	ir "github.com/finos/morphir-go/pkg/models/ir"
)

// LocalDateModuleName returns the module name for Morphir.SDK.LocalDate
func LocalDateModuleName() ir.ModuleName {
	return ir.PathFromString("LocalDate")
}

// LocalDateModuleSpec returns the module specification for Morphir.SDK.LocalDate
func LocalDateModuleSpec() ir.ModuleSpecification[ir.Unit] {
	return ir.NewModuleSpecification(
		localDateTypes(),
		localDateValues(),
		nil,
	)
}

// localDateTypes returns the type specifications for the LocalDate module
func localDateTypes() []ir.ModuleSpecificationType[ir.Unit] {
	return []ir.ModuleSpecificationType[ir.Unit]{
		// LocalDate type
		ir.ModuleSpecificationTypeFromParts[ir.Unit](
			ir.NameFromString("LocalDate"),
			ir.NewDocumented(
				"Type that represents a date concept.",
				ir.NewOpaqueTypeSpecification[ir.Unit](nil),
			),
		),

		// Month type (custom type with 12 constructors)
		ir.ModuleSpecificationTypeFromParts[ir.Unit](
			ir.NameFromString("Month"),
			ir.NewDocumented(
				"Type that represents months of the year.",
				ir.NewCustomTypeSpecification[ir.Unit](
					nil,
					ir.TypeConstructors[ir.Unit]{
						ir.TypeConstructorFromParts[ir.Unit](ir.NameFromString("January"), nil),
						ir.TypeConstructorFromParts[ir.Unit](ir.NameFromString("February"), nil),
						ir.TypeConstructorFromParts[ir.Unit](ir.NameFromString("March"), nil),
						ir.TypeConstructorFromParts[ir.Unit](ir.NameFromString("April"), nil),
						ir.TypeConstructorFromParts[ir.Unit](ir.NameFromString("May"), nil),
						ir.TypeConstructorFromParts[ir.Unit](ir.NameFromString("June"), nil),
						ir.TypeConstructorFromParts[ir.Unit](ir.NameFromString("July"), nil),
						ir.TypeConstructorFromParts[ir.Unit](ir.NameFromString("August"), nil),
						ir.TypeConstructorFromParts[ir.Unit](ir.NameFromString("September"), nil),
						ir.TypeConstructorFromParts[ir.Unit](ir.NameFromString("October"), nil),
						ir.TypeConstructorFromParts[ir.Unit](ir.NameFromString("November"), nil),
						ir.TypeConstructorFromParts[ir.Unit](ir.NameFromString("December"), nil),
					},
				),
			),
		),

		// DayOfWeek type (custom type with 7 constructors)
		ir.ModuleSpecificationTypeFromParts[ir.Unit](
			ir.NameFromString("DayOfWeek"),
			ir.NewDocumented(
				"Type that represents days of the week.",
				ir.NewCustomTypeSpecification[ir.Unit](
					nil,
					ir.TypeConstructors[ir.Unit]{
						ir.TypeConstructorFromParts[ir.Unit](ir.NameFromString("Monday"), nil),
						ir.TypeConstructorFromParts[ir.Unit](ir.NameFromString("Tuesday"), nil),
						ir.TypeConstructorFromParts[ir.Unit](ir.NameFromString("Wednesday"), nil),
						ir.TypeConstructorFromParts[ir.Unit](ir.NameFromString("Thursday"), nil),
						ir.TypeConstructorFromParts[ir.Unit](ir.NameFromString("Friday"), nil),
						ir.TypeConstructorFromParts[ir.Unit](ir.NameFromString("Saturday"), nil),
						ir.TypeConstructorFromParts[ir.Unit](ir.NameFromString("Sunday"), nil),
					},
				),
			),
		),
	}
}

// localDateValues returns the value specifications for the LocalDate module
func localDateValues() []ir.ModuleSpecificationValue[ir.Unit] {
	return []ir.ModuleSpecificationValue[ir.Unit]{
		// Construction
		VSpec("fromCalendarDate", []VSpecInput{
			{Name: "year", Type: intType()},
			{Name: "month", Type: MonthType()},
			{Name: "day", Type: intType()},
		}, LocalDateType(),
			"Construct a date from a year, month, and day."),

		VSpec("fromOrdinalDate", []VSpecInput{
			{Name: "year", Type: intType()},
			{Name: "dayOfYear", Type: intType()},
		}, LocalDateType(),
			"Construct a date from a year and day of year (1-366)."),

		VSpec("fromParts", []VSpecInput{
			{Name: "year", Type: intType()},
			{Name: "month", Type: intType()},
			{Name: "day", Type: intType()},
		}, MaybeType(LocalDateType()),
			"Construct a date from integer parts. Returns Nothing if invalid."),

		VSpec("fromISO", []VSpecInput{
			{Name: "iso", Type: StringType()},
		}, MaybeType(LocalDateType()),
			"Parse a date from ISO 8601 format."),

		// Conversion
		VSpec("toISOString", []VSpecInput{
			{Name: "date", Type: LocalDateType()},
		}, StringType(),
			"Convert a date to ISO 8601 string format."),

		// Accessors
		VSpec("year", []VSpecInput{
			{Name: "localDate", Type: LocalDateType()},
		}, intType(),
			"Extract the year from a date."),

		VSpec("month", []VSpecInput{
			{Name: "localDate", Type: LocalDateType()},
		}, MonthType(),
			"Extract the month from a date."),

		VSpec("monthNumber", []VSpecInput{
			{Name: "localDate", Type: LocalDateType()},
		}, intType(),
			"Extract the month as an integer (1-12) from a date."),

		VSpec("day", []VSpecInput{
			{Name: "localDate", Type: LocalDateType()},
		}, intType(),
			"Extract the day of month from a date."),

		VSpec("dayOfWeek", []VSpecInput{
			{Name: "localDate", Type: LocalDateType()},
		}, DayOfWeekType(),
			"Determine the day of week for a date."),

		// Month utilities
		VSpec("monthToInt", []VSpecInput{
			{Name: "m", Type: MonthType()},
		}, intType(),
			"Convert a month to its integer representation (1-12)."),

		// Predicates
		VSpec("isWeekend", []VSpecInput{
			{Name: "localDate", Type: LocalDateType()},
		}, boolType(),
			"Determine if a date falls on a weekend (Saturday or Sunday)."),

		VSpec("isWeekday", []VSpecInput{
			{Name: "localDate", Type: LocalDateType()},
		}, boolType(),
			"Determine if a date falls on a weekday (Monday through Friday)."),

		// Arithmetic - Addition
		VSpec("addDays", []VSpecInput{
			{Name: "offset", Type: intType()},
			{Name: "startDate", Type: LocalDateType()},
		}, LocalDateType(),
			"Add a number of days to a date."),

		VSpec("addWeeks", []VSpecInput{
			{Name: "offset", Type: intType()},
			{Name: "startDate", Type: LocalDateType()},
		}, LocalDateType(),
			"Add a number of weeks to a date."),

		VSpec("addMonths", []VSpecInput{
			{Name: "offset", Type: intType()},
			{Name: "startDate", Type: LocalDateType()},
		}, LocalDateType(),
			"Add a number of months to a date."),

		VSpec("addYears", []VSpecInput{
			{Name: "offset", Type: intType()},
			{Name: "startDate", Type: LocalDateType()},
		}, LocalDateType(),
			"Add a number of years to a date."),

		// Arithmetic - Difference
		VSpec("diffInDays", []VSpecInput{
			{Name: "date1", Type: LocalDateType()},
			{Name: "date2", Type: LocalDateType()},
		}, intType(),
			"Calculate the difference between two dates in days."),

		VSpec("diffInWeeks", []VSpecInput{
			{Name: "date1", Type: LocalDateType()},
			{Name: "date2", Type: LocalDateType()},
		}, intType(),
			"Calculate the difference between two dates in weeks."),

		VSpec("diffInMonths", []VSpecInput{
			{Name: "date1", Type: LocalDateType()},
			{Name: "date2", Type: LocalDateType()},
		}, intType(),
			"Calculate the difference between two dates in months."),

		VSpec("diffInYears", []VSpecInput{
			{Name: "date1", Type: LocalDateType()},
			{Name: "date2", Type: LocalDateType()},
		}, intType(),
			"Calculate the difference between two dates in years."),
	}
}

// LocalDateType creates a LocalDate type reference
func LocalDateType() ir.Type[ir.Unit] {
	return ir.NewTypeReference(
		ir.Unit{},
		ToFQName(LocalDateModuleName(), "LocalDate"),
		nil,
	)
}

// MonthType creates a Month type reference
func MonthType() ir.Type[ir.Unit] {
	return ir.NewTypeReference(
		ir.Unit{},
		ToFQName(LocalDateModuleName(), "Month"),
		nil,
	)
}

// DayOfWeekType creates a DayOfWeek type reference
func DayOfWeekType() ir.Type[ir.Unit] {
	return ir.NewTypeReference(
		ir.Unit{},
		ToFQName(LocalDateModuleName(), "DayOfWeek"),
		nil,
	)
}
