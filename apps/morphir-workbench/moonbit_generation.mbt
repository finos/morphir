///|
/// Only the private local worker declares binary encoding. Connected v1 remains opaque.
fn moonbit_output(input : @moonbit.Input) -> Json {
  try {
    let output = @moonbit.generate(input)
    @wire.obj([
      ("generationWarnings", Json::array(output.warnings.map(naming_warning))),
      (
        "artifacts",
        Json::array(
          output.artifacts.map(artifact => {
            let (content, binary, encoding) = match artifact.content {
              Text(text) => (text, false, "utf-8")
              Binary(bytes) => (@base64.encode(bytes[:]), true, "base64")
            }
            @wire.obj([
              ("path", @wire.text(artifact.path)),
              ("content", @wire.text(content)),
              ("binary", Json::boolean(binary)),
              ("encoding", @wire.text(encoding)),
            ])
          }),
        ),
      ),
    ])
  } catch {
    @moonbit.Invalid(code, node, detail) =>
      @wire.obj([
        ("artifacts", Json::array([])),
        (
          "generationDiagnostics",
          Json::array([
            @wire.obj([
              ("code", @wire.text(code)),
              ("nodePath", @wire.text(node)),
              ("detail", @wire.text(detail)),
            ]),
          ]),
        ),
        (
          "generationMessage",
          @wire.text(
            "MoonBit generation failed: " + code + " at " + node + ": " + detail,
          ),
        ),
      ])
  }
}
