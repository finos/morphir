package nbformat

// OutputType represents the type of a code cell output.
type OutputType string

const (
	OutputTypeStream        OutputType = "stream"
	OutputTypeDisplayData   OutputType = "display_data"
	OutputTypeExecuteResult OutputType = "execute_result"
	OutputTypeError         OutputType = "error"
)

// Output is a sealed interface representing a code cell output.
// The only implementations are [StreamOutput], [DisplayDataOutput],
// [ExecuteResultOutput], and [ErrorOutput].
type Output interface {
	// isOutput is a marker method that seals the interface.
	isOutput()

	// OutputType returns the type of the output.
	OutputType() OutputType
}

// StreamName represents the name of a stream output.
type StreamName string

const (
	StreamStdout StreamName = "stdout"
	StreamStderr StreamName = "stderr"
)

// StreamOutput represents output written to stdout or stderr.
type StreamOutput struct {
	name StreamName
	text string
}

func (StreamOutput) isOutput()              {}
func (StreamOutput) OutputType() OutputType { return OutputTypeStream }

// Name returns the stream name (stdout or stderr).
func (o StreamOutput) Name() StreamName { return o.name }

// Text returns the stream text content.
func (o StreamOutput) Text() string { return o.text }

// NewStreamOutput creates a new stream output.
func NewStreamOutput(name StreamName, text string) StreamOutput {
	return StreamOutput{name: name, text: text}
}

// NewStdoutOutput creates a new stdout stream output.
func NewStdoutOutput(text string) StreamOutput {
	return StreamOutput{name: StreamStdout, text: text}
}

// NewStderrOutput creates a new stderr stream output.
func NewStderrOutput(text string) StreamOutput {
	return StreamOutput{name: StreamStderr, text: text}
}

// WithName returns a new StreamOutput with the name set.
func (o StreamOutput) WithName(name StreamName) StreamOutput {
	o.name = name
	return o
}

// WithText returns a new StreamOutput with the text set.
func (o StreamOutput) WithText(text string) StreamOutput {
	o.text = text
	return o
}

// DisplayDataOutput represents rich display data output.
type DisplayDataOutput struct {
	data     MimeBundle
	metadata MimeBundle
}

func (DisplayDataOutput) isOutput()              {}
func (DisplayDataOutput) OutputType() OutputType { return OutputTypeDisplayData }

// Data returns the output data as a MimeBundle.
func (o DisplayDataOutput) Data() MimeBundle { return o.data.clone() }

// Metadata returns the output metadata as a MimeBundle.
func (o DisplayDataOutput) Metadata() MimeBundle { return o.metadata.clone() }

// NewDisplayDataOutput creates a new display data output.
func NewDisplayDataOutput(data MimeBundle) DisplayDataOutput {
	return DisplayDataOutput{data: data.clone()}
}

// WithData returns a new DisplayDataOutput with the data set.
func (o DisplayDataOutput) WithData(data MimeBundle) DisplayDataOutput {
	o.data = data.clone()
	return o
}

// WithMetadata returns a new DisplayDataOutput with the metadata set.
func (o DisplayDataOutput) WithMetadata(metadata MimeBundle) DisplayDataOutput {
	o.metadata = metadata.clone()
	return o
}

// ExecuteResultOutput represents the result of executing a code cell.
type ExecuteResultOutput struct {
	executionCount int
	data           MimeBundle
	metadata       MimeBundle
}

func (ExecuteResultOutput) isOutput()              {}
func (ExecuteResultOutput) OutputType() OutputType { return OutputTypeExecuteResult }

// ExecutionCount returns the execution count.
func (o ExecuteResultOutput) ExecutionCount() int { return o.executionCount }

// Data returns the output data as a MimeBundle.
func (o ExecuteResultOutput) Data() MimeBundle { return o.data.clone() }

// Metadata returns the output metadata as a MimeBundle.
func (o ExecuteResultOutput) Metadata() MimeBundle { return o.metadata.clone() }

// NewExecuteResultOutput creates a new execute result output.
func NewExecuteResultOutput(executionCount int, data MimeBundle) ExecuteResultOutput {
	return ExecuteResultOutput{executionCount: executionCount, data: data.clone()}
}

// WithExecutionCount returns a new ExecuteResultOutput with the execution count set.
func (o ExecuteResultOutput) WithExecutionCount(count int) ExecuteResultOutput {
	o.executionCount = count
	return o
}

// WithData returns a new ExecuteResultOutput with the data set.
func (o ExecuteResultOutput) WithData(data MimeBundle) ExecuteResultOutput {
	o.data = data.clone()
	return o
}

// WithMetadata returns a new ExecuteResultOutput with the metadata set.
func (o ExecuteResultOutput) WithMetadata(metadata MimeBundle) ExecuteResultOutput {
	o.metadata = metadata.clone()
	return o
}

// ErrorOutput represents an error that occurred during execution.
type ErrorOutput struct {
	ename     string
	evalue    string
	traceback []string
}

func (ErrorOutput) isOutput()              {}
func (ErrorOutput) OutputType() OutputType { return OutputTypeError }

// Ename returns the error name/type.
func (o ErrorOutput) Ename() string { return o.ename }

// Evalue returns the error value/message.
func (o ErrorOutput) Evalue() string { return o.evalue }

// Traceback returns a copy of the error traceback.
func (o ErrorOutput) Traceback() []string {
	if len(o.traceback) == 0 {
		return nil
	}
	result := make([]string, len(o.traceback))
	copy(result, o.traceback)
	return result
}

// NewErrorOutput creates a new error output.
func NewErrorOutput(ename, evalue string, traceback []string) ErrorOutput {
	var tb []string
	if len(traceback) > 0 {
		tb = make([]string, len(traceback))
		copy(tb, traceback)
	}
	return ErrorOutput{ename: ename, evalue: evalue, traceback: tb}
}

// WithEname returns a new ErrorOutput with the error name set.
func (o ErrorOutput) WithEname(ename string) ErrorOutput {
	o.ename = ename
	return o
}

// WithEvalue returns a new ErrorOutput with the error value set.
func (o ErrorOutput) WithEvalue(evalue string) ErrorOutput {
	o.evalue = evalue
	return o
}

// WithTraceback returns a new ErrorOutput with the traceback set.
func (o ErrorOutput) WithTraceback(traceback []string) ErrorOutput {
	if len(traceback) == 0 {
		o.traceback = nil
	} else {
		o.traceback = make([]string, len(traceback))
		copy(o.traceback, traceback)
	}
	return o
}
