///|
fn capture(text : String) -> @worksheet.CapturedWorksheetSource raise {
  @worksheet.CapturedWorksheetSource::new(
    @worksheet.WorksheetId::parse("fixture"),
    @worksheet.SourceRevision::new(0),
    text,
  )
}

///|
fn field(value : Json, key : String) -> Json {
  match value {
    Object(fields) => fields.get(key).unwrap_or(Json::null())
    _ => Json::null()
  }
}

///|
test "forms and whole-line comments become ordered cells without lexical guesses" {
  let source = capture(
    ";; # Totals\r\n;; 😀\r\n(define x 2) ;; inline\r\n#|\n;; hidden\n|#\n#;(ignored\n;; discarded\n)\n(+ x\n;; nested\n3)\n;; tail\n",
  )
  let exported = @notebook.export_notebook(source, Ipynb)
  assert_eq(exported.cells(), 4)
  let cells = @nbformat.parse(exported.content()).cells()
  assert_eq(cells[0].source(), Some("# Totals\n😀"))
  assert_eq(cells[1].source(), Some("(define x 2)"))
  assert_eq(cells[2].source(), Some("(+ x\n;; nested\n3)"))
  assert_eq(cells[3].source(), Some("tail"))
  assert_eq(
    field(
      field(@nbformat.parse(exported.content()).metadata().to_json(), "morphir"),
      "profile",
    ),
    Json::string(@notebook.PROFILE),
  )
}

///|
test "Jupyter observations retain previews and typed JSON; failures are error outputs" {
  let source = capture("(+ 1 2)\n(unknown-function)")
  let report = @worksheet.WorksheetRequest::new(source).evaluate()
  let exported = @notebook.export_notebook(source, Ipynb, report~)
  let cells = @nbformat.parse(exported.content()).cells()
  assert_eq(cells[0].outputs().length(), 1)
  assert_eq(cells[1].outputs().length(), 1)
  let success = cells[0].outputs()[0].to_json()
  assert_eq(field(success, "output_type"), Json::string("execute_result"))
  assert_eq(
    field(field(success, "data"), "text/plain"),
    Json::string(report.observations()[0].preview()),
  )
  assert_eq(
    field(
      field(field(success, "data"), "application/vnd.morphir.observation+json"),
      "outcome",
    ),
    report.observations()[0].outcome().to_json(),
  )
  assert_eq(cells[1].outputs()[0].output_type(), "error")
}

///|
test "Jupyter and DIB round trips preserve forms comments and evaluation" {
  let source = capture(
    ";; # Totals\n(define prices '(3 4 5))\n;; Sum\n(apply + prices)\n",
  )
  let original = @worksheet.WorksheetRequest::new(source).evaluate()
  for format in [@notebook.Ipynb, @notebook.Dib] {
    let exported = @notebook.export_notebook(source, format)
    let imported = @notebook.import_notebook(exported.content(), format)
    assert_eq(imported.cells(), 4)
    assert_eq(imported.skipped(), [])
    assert_eq(
      imported.source(),
      ";; # Totals\n\n(define prices '(3 4 5))\n\n;; Sum\n\n(apply + prices)\n",
    )
    let restored = @worksheet.WorksheetRequest::new(capture(imported.source())).evaluate()
    assert_eq(
      restored
      .observations()
      .map(row => (row.expression(), row.preview(), row.outcome())),
      original
      .observations()
      .map(row => (row.expression(), row.preview(), row.outcome())),
    )
  }
}

///|
test "DIB outputs are refused and stale observations cannot be attached" {
  let source = capture("42")
  let report = @worksheet.WorksheetRequest::new(source).evaluate()
  let refused = try {
    ignore(@notebook.export_notebook(source, Dib, report~))
    false
  } catch {
    @notebook.OutputsRequireJupyter => true
    _ => false
  }
  assert_true(refused)
  let stale = try {
    ignore(@notebook.export_notebook(capture("43"), Ipynb, report~))
    false
  } catch {
    @notebook.StaleObservations => true
    _ => false
  }
  assert_true(stale)
}

///|
test "mixed language notebooks skip foreign code and raw cells with named warnings" {
  let content = "{\"nbformat\":4,\"nbformat_minor\":4,\"metadata\":{\"language_info\":{\"name\":\"scheme\"}},\"cells\":[{\"cell_type\":\"code\",\"metadata\":{},\"source\":\"(+ 1 2)\",\"outputs\":[],\"execution_count\":null},{\"cell_type\":\"code\",\"metadata\":{\"language\":\"python\"},\"source\":\"print(1)\",\"outputs\":[],\"execution_count\":null},{\"cell_type\":\"raw\",\"metadata\":{},\"source\":\"raw\"},{\"cell_type\":\"markdown\",\"metadata\":{},\"source\":\"# End\"}]}"
  let imported = @notebook.import_notebook(content, Ipynb)
  assert_eq(imported.source(), "(+ 1 2)\n\n;; # End\n")
  assert_eq(imported.skipped().map(cell => (cell.index(), cell.name())), [
    (1, "cell-1"),
    (2, "cell-2"),
  ])
  let dib = @notebook.import_notebook(
    "#!scheme\n42\n#!csharp\nConsole.WriteLine(1);\n#!markdown\n# End",
    Dib,
  )
  assert_eq(dib.source(), "42\n\n;; # End\n")
  assert_eq(dib.skipped().length(), 1)
}

///|
test "invalid notebooks and syntax failures never produce a worksheet or valid prefix" {
  for content in ["{", "{\"nbformat\":3}"] {
    let refused = try {
      ignore(@notebook.import_notebook(content, Ipynb))
      false
    } catch {
      _ => true
    }
    assert_true(refused)
  }
  let bad = try {
    ignore(@notebook.export_notebook(capture("42 ("), Ipynb))
    false
  } catch {
    _ => true
  }
  assert_true(bad)
  let invalid_dib = try {
    ignore(@notebook.import_notebook("#!meta\n{bad}", Dib))
    false
  } catch {
    _ => true
  }
  assert_true(invalid_dib)
}

///|
test "DIB empty cells retain counts and skipped cell indexes through the public lossless codec" {
  let imported = @notebook.import_notebook(
    "#!csharp\n#!scheme\n42\n#!markdown\n",
    Dib,
  )
  assert_eq(imported.cells(), 3)
  assert_eq(imported.skipped().map(cell => cell.index()), [0])
  let report = @worksheet.WorksheetRequest::new(capture(imported.source())).evaluate()
  assert_eq(report.observations().length(), 1)
  assert_eq(report.observations()[0].preview(), "42")
  let empty_comment = @notebook.export_notebook(capture(";;\n42"), Dib)
  let restored = @notebook.import_notebook(empty_comment.content(), Dib)
  assert_eq(restored.cells(), 2)
}
