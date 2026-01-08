# Go Code Generation Examples

This directory contains examples demonstrating the IR to Go code generation capabilities.

## Running the Examples

```bash
# Run the simple generation example
go run simple_gen.go
```

## Example: simple_gen.go

This example demonstrates:
1. Creating a Morphir IR module with a type alias
2. Converting the IR to Go domain model
3. Emitting Go source code with proper formatting
4. Using the pipeline step for full generation
5. Generating go.mod files

The example creates a simple `UserID` type alias and generates Go code from it, showing both the direct domain model usage and the pipeline step approach.

## Expected Output

The example will:
- Print the package information
- Display the generated Go source code
- List all generated files
- Show the contents of the generated go.mod file

The generated Go code follows standard Go conventions:
- Proper package declaration
- gofmt formatted
- Exported types (capitalized)
- Documentation comments
