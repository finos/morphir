//! Native host for the transport-independent evaluation contract.

use clap::Args;
use miette::{Context, IntoDiagnostic, Result};
#[cfg(feature = "rego")]
use morphir_evaluator::Evaluator;
use morphir_evaluator::ir_draft::IrEvaluationRequest;
use morphir_evaluator::{EvaluationOutcome, EvaluationReport, EvaluationRequest, ProviderId};
use std::{fs, path::PathBuf};

#[derive(Args, Clone, Debug)]
pub struct EvalArgs {
    /// Path to a version 1 or native IR draft evaluation request JSON file
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
    if serde_json::from_slice::<serde_json::Value>(&source)
        .ok()
        .and_then(|request| request.get("version").cloned())
        .is_some_and(|version| version.is_string())
    {
        let request = IrEvaluationRequest::from_slice(&source)
            .into_diagnostic()
            .wrap_err("invalid evaluation request")?;
        let report = request.evaluate();
        if args.json {
            println!("{}", serde_json::to_string(&report).into_diagnostic()?);
        } else {
            for result in &report.results {
                match &result.value {
                    Some(value) => println!(
                        "{}: {}",
                        result.entrypoint,
                        serde_json::to_string(value).into_diagnostic()?
                    ),
                    None => println!(
                        "{}: error: {}",
                        result.entrypoint,
                        result.message.as_deref().unwrap_or("unknown error")
                    ),
                }
            }
        }
        if report.has_errors() {
            miette::bail!("evaluation failed; see the evaluation report");
        }
        return Ok(());
    }
    let request: EvaluationRequest = serde_json::from_slice(&source)
        .into_diagnostic()
        .wrap_err("invalid evaluation request")?;
    let report = evaluate(&request)?;
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

// Native registration only. Installed extension providers require protocol
// capability negotiation before they can implement this contract.
#[cfg(feature = "rego")]
fn evaluate(request: &EvaluationRequest) -> Result<EvaluationReport> {
    let evaluator: &dyn Evaluator = match request.provider() {
        ProviderId::Rego => &morphir_opa::RegoEvaluator,
    };
    Ok(evaluator.evaluate(request))
}

#[cfg(not(feature = "rego"))]
fn evaluate(request: &EvaluationRequest) -> Result<EvaluationReport> {
    match request.provider() {
        ProviderId::Rego => miette::bail!(
            "the Rego evaluator is unavailable: this binary was built without the `rego` \
             feature (enabled by default). Rebuild without `--no-default-features`, or with \
             `--features rego`, to evaluate Rego programs."
        ),
    }
}
