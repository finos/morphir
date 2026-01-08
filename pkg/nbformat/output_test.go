package nbformat

import (
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestStreamOutput(t *testing.T) {
	t.Run("NewStreamOutput creates output", func(t *testing.T) {
		output := NewStreamOutput(StreamStdout, "hello world")
		assert.Equal(t, OutputTypeStream, output.OutputType())
		assert.Equal(t, StreamStdout, output.Name())
		assert.Equal(t, "hello world", output.Text())
	})

	t.Run("NewStdoutOutput creates stdout output", func(t *testing.T) {
		output := NewStdoutOutput("stdout text")
		assert.Equal(t, StreamStdout, output.Name())
		assert.Equal(t, "stdout text", output.Text())
	})

	t.Run("NewStderrOutput creates stderr output", func(t *testing.T) {
		output := NewStderrOutput("error text")
		assert.Equal(t, StreamStderr, output.Name())
		assert.Equal(t, "error text", output.Text())
	})

	t.Run("WithName sets name immutably", func(t *testing.T) {
		original := NewStdoutOutput("text")
		modified := original.WithName(StreamStderr)

		assert.Equal(t, StreamStdout, original.Name())
		assert.Equal(t, StreamStderr, modified.Name())
	})

	t.Run("WithText sets text immutably", func(t *testing.T) {
		original := NewStdoutOutput("original")
		modified := original.WithText("modified")

		assert.Equal(t, "original", original.Text())
		assert.Equal(t, "modified", modified.Text())
	})

	t.Run("implements Output interface", func(t *testing.T) {
		var output Output = NewStdoutOutput("text")
		assert.Equal(t, OutputTypeStream, output.OutputType())
	})
}

func TestDisplayDataOutput(t *testing.T) {
	t.Run("NewDisplayDataOutput creates output", func(t *testing.T) {
		data := NewMimeBundle().WithData("text/plain", "hello")
		output := NewDisplayDataOutput(data)

		assert.Equal(t, OutputTypeDisplayData, output.OutputType())
		val, ok := output.Data().Get("text/plain")
		assert.True(t, ok)
		assert.Equal(t, "hello", val)
	})

	t.Run("Data returns defensive copy", func(t *testing.T) {
		data := NewMimeBundle().WithData("text/plain", "hello")
		output := NewDisplayDataOutput(data)

		// Modify the returned data
		outputData := output.Data()
		_ = outputData.WithData("text/html", "<b>test</b>")

		// Original output should be unaffected
		_, ok := output.Data().Get("text/html")
		assert.False(t, ok)
	})

	t.Run("WithData sets data immutably", func(t *testing.T) {
		original := NewDisplayDataOutput(NewMimeBundle().WithData("text/plain", "original"))
		modified := original.WithData(NewMimeBundle().WithData("text/plain", "modified"))

		origVal, _ := original.Data().Get("text/plain")
		modVal, _ := modified.Data().Get("text/plain")

		assert.Equal(t, "original", origVal)
		assert.Equal(t, "modified", modVal)
	})

	t.Run("WithMetadata sets metadata immutably", func(t *testing.T) {
		original := NewDisplayDataOutput(NewMimeBundle())
		modified := original.WithMetadata(NewMimeBundle().WithData("key", "value"))

		assert.Nil(t, original.Metadata().Data())
		val, ok := modified.Metadata().Get("key")
		assert.True(t, ok)
		assert.Equal(t, "value", val)
	})

	t.Run("implements Output interface", func(t *testing.T) {
		var output Output = NewDisplayDataOutput(NewMimeBundle())
		assert.Equal(t, OutputTypeDisplayData, output.OutputType())
	})
}

func TestExecuteResultOutput(t *testing.T) {
	t.Run("NewExecuteResultOutput creates output", func(t *testing.T) {
		data := NewMimeBundle().WithData("text/plain", "result")
		output := NewExecuteResultOutput(5, data)

		assert.Equal(t, OutputTypeExecuteResult, output.OutputType())
		assert.Equal(t, 5, output.ExecutionCount())
		val, ok := output.Data().Get("text/plain")
		assert.True(t, ok)
		assert.Equal(t, "result", val)
	})

	t.Run("WithExecutionCount sets count immutably", func(t *testing.T) {
		original := NewExecuteResultOutput(1, NewMimeBundle())
		modified := original.WithExecutionCount(10)

		assert.Equal(t, 1, original.ExecutionCount())
		assert.Equal(t, 10, modified.ExecutionCount())
	})

	t.Run("WithData sets data immutably", func(t *testing.T) {
		original := NewExecuteResultOutput(1, NewMimeBundle().WithData("text/plain", "original"))
		modified := original.WithData(NewMimeBundle().WithData("text/plain", "modified"))

		origVal, _ := original.Data().Get("text/plain")
		modVal, _ := modified.Data().Get("text/plain")

		assert.Equal(t, "original", origVal)
		assert.Equal(t, "modified", modVal)
	})

	t.Run("implements Output interface", func(t *testing.T) {
		var output Output = NewExecuteResultOutput(1, NewMimeBundle())
		assert.Equal(t, OutputTypeExecuteResult, output.OutputType())
	})
}

func TestErrorOutput(t *testing.T) {
	t.Run("NewErrorOutput creates output", func(t *testing.T) {
		traceback := []string{
			"Traceback (most recent call last):",
			"  File \"<stdin>\", line 1",
			"ZeroDivisionError: division by zero",
		}
		output := NewErrorOutput("ZeroDivisionError", "division by zero", traceback)

		assert.Equal(t, OutputTypeError, output.OutputType())
		assert.Equal(t, "ZeroDivisionError", output.Ename())
		assert.Equal(t, "division by zero", output.Evalue())
		assert.Equal(t, traceback, output.Traceback())
	})

	t.Run("Traceback creates defensive copy on input", func(t *testing.T) {
		traceback := []string{"line 1", "line 2"}
		output := NewErrorOutput("Error", "msg", traceback)

		// Modify original slice
		traceback[0] = "modified"

		// Output should be unaffected
		assert.Equal(t, "line 1", output.Traceback()[0])
	})

	t.Run("Traceback returns defensive copy", func(t *testing.T) {
		output := NewErrorOutput("Error", "msg", []string{"line 1", "line 2"})

		tb := output.Traceback()
		tb[0] = "modified"

		// Original output should be unaffected
		assert.Equal(t, "line 1", output.Traceback()[0])
	})

	t.Run("WithEname sets ename immutably", func(t *testing.T) {
		original := NewErrorOutput("Error1", "msg", nil)
		modified := original.WithEname("Error2")

		assert.Equal(t, "Error1", original.Ename())
		assert.Equal(t, "Error2", modified.Ename())
	})

	t.Run("WithEvalue sets evalue immutably", func(t *testing.T) {
		original := NewErrorOutput("Error", "msg1", nil)
		modified := original.WithEvalue("msg2")

		assert.Equal(t, "msg1", original.Evalue())
		assert.Equal(t, "msg2", modified.Evalue())
	})

	t.Run("WithTraceback sets traceback immutably", func(t *testing.T) {
		original := NewErrorOutput("Error", "msg", []string{"line 1"})
		modified := original.WithTraceback([]string{"new line 1", "new line 2"})

		require.Len(t, original.Traceback(), 1)
		require.Len(t, modified.Traceback(), 2)
		assert.Equal(t, "line 1", original.Traceback()[0])
		assert.Equal(t, "new line 1", modified.Traceback()[0])
	})

	t.Run("WithTraceback nil clears traceback", func(t *testing.T) {
		original := NewErrorOutput("Error", "msg", []string{"line 1"})
		modified := original.WithTraceback(nil)

		require.Len(t, original.Traceback(), 1)
		assert.Nil(t, modified.Traceback())
	})

	t.Run("implements Output interface", func(t *testing.T) {
		var output Output = NewErrorOutput("Error", "msg", nil)
		assert.Equal(t, OutputTypeError, output.OutputType())
	})
}

func TestOutputTypes(t *testing.T) {
	t.Run("all output types are distinct", func(t *testing.T) {
		types := []OutputType{
			OutputTypeStream,
			OutputTypeDisplayData,
			OutputTypeExecuteResult,
			OutputTypeError,
		}

		seen := make(map[OutputType]bool)
		for _, ot := range types {
			assert.False(t, seen[ot], "duplicate output type: %s", ot)
			seen[ot] = true
		}
	})

	t.Run("output types have correct string values", func(t *testing.T) {
		assert.Equal(t, OutputType("stream"), OutputTypeStream)
		assert.Equal(t, OutputType("display_data"), OutputTypeDisplayData)
		assert.Equal(t, OutputType("execute_result"), OutputTypeExecuteResult)
		assert.Equal(t, OutputType("error"), OutputTypeError)
	})
}

func TestStreamName(t *testing.T) {
	t.Run("stream names have correct values", func(t *testing.T) {
		assert.Equal(t, StreamName("stdout"), StreamStdout)
		assert.Equal(t, StreamName("stderr"), StreamStderr)
	})
}
