//! Native host for the transport-independent evaluation contract.

use clap::Args;
use miette::{Context, IntoDiagnostic, Result};
use morphir_evaluator::{EvaluationOutcome, EvaluationRequest, Evaluator, ProviderId};
use std::{fs, path::PathBuf};

#[derive(Args, Clone, Debug)]
pub struct EvalArgs {
    /// Path to a version 1 evaluation request JSON file
    #[arg(long, value_name = "FILE")]
    pub request: PathBuf,
    /// Print the versioned evaluation report as JSON
    #[arg(long)]
    pub json: bool,
}

pub fn run_eval(args: EvalArgs) -> Result<()> {
    let source = fs::read(&args.request)
        .into_diagnostic()
        .wrap_err_with(|| format!("cannot read evaluation request {}", args.request.display()))?;
    let request: EvaluationRequest = serde_json::from_slice(&source)
        .into_diagnostic()
        .wrap_err("invalid evaluation request")?;
    // Native registration only. Installed extension providers require protocol
    // capability negotiation before they can implement this contract.
    let evaluator: &dyn Evaluator = match request.provider() {
        ProviderId::Rego => &morphir_opa::RegoEvaluator,
    };
    let report = evaluator.evaluate(&request);
    if args.json {
        println!("{}", serde_json::to_string(&report).into_diagnostic()?);
    } else {
        for result in &report.results {
            match &result.outcome {
                EvaluationOutcome::Value { value } => println!("{}: {value}", result.entrypoint),
                EvaluationOutcome::Undefined => println!("{}: undefined", result.entrypoint),
                EvaluationOutcome::Error { message } => {
                    println!("{}: error: {message}", result.entrypoint)
                }
            }
        }
    }
    if report.has_errors() {
        miette::bail!("evaluation failed; see the evaluation report");
    }
    Ok(())
}
