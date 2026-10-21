//! Prospective child of existing source_compile::tests, reusing its funded helpers.
//! Representation-only injection into the private latch; no genuine source-fault claim.
use super::*;

#[test]
fn preparation_fault_transfer_moves_existing_owned_diagnostic_without_cloning() {
    let sources = ReviewedSources::selected();
    let mut decode = decoder();
    let verifier = SourceVerifier::new(&sources, &mut decode).unwrap();
    let mut aliases = closure(1_000_000);
    let mut expanded = expansion(1_073_741_824);
    let mut compiler = CaseCompiler::new(verifier, &mut aliases, &mut expanded);
    let diagnostic = String::from("already owned decoder diagnostic");
    let pointer = diagnostic.as_ptr();
    let capacity = diagnostic.capacity();
    compiler.fault = Some(CompilationError::Source(SourceError::Decode(
        crate::workbench::model_originals::workflow::DecodeError::Value(diagnostic),
    )));
    let owned = compiler
        .into_fault()
        .expect("the exact private latch was populated");
    let CompilationError::Source(SourceError::Decode(
        crate::workbench::model_originals::workflow::DecodeError::Value(diagnostic),
    )) = owned
    else {
        panic!("preserve exact nested cause")
    };
    assert_eq!(diagnostic.as_ptr(), pointer);
    assert_eq!(diagnostic.capacity(), capacity);
    assert_eq!(diagnostic, "already owned decoder diagnostic");
    // The compiler is consumed; no healthy-looking reuse/reset is possible.
}
