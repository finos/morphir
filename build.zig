const std = @import("std");

pub fn build(b: *std.Build) void {
    const run_tool = b.option(JavascriptRunTool, "js-runtool", "JavaScript run tool, such as npx or bun.") orelse JavascriptRunTool.bunx;

    // Setup verification step for the elm package
    const verify_elm_package = b.step("verify-elm-package", "Verify that the finos/morphir Elm package is valid and okay to publish.");
    const check_elm_docs = b.step("check-elm-docs", "Check that the Elm package documentation is in a valid state.");

    const elm_make_docs = switch (run_tool) {
        JavascriptRunTool.bunx => b.addSystemCommand(&.{ "bunx", "elm", "make" }),
        JavascriptRunTool.npx => b.addSystemCommand(&.{ "npx", "elm", "make" }),
    };
    elm_make_docs.addArg("--docs");

    const elm_docs_output = elm_make_docs.addOutputFileArg("docs.json");

    check_elm_docs
        .dependOn(&b.addInstallFileWithDir(elm_docs_output, .prefix, b.pathJoin(&.{ "elm-out/finos/morphir", "docs.json" })).step);

    verify_elm_package.dependOn(check_elm_docs);
}

const JavascriptRunTool = enum { bunx, npx };
