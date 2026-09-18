//! Native embedded Rego provider. It does not read files or launch processes.

use morphir_evaluator::{
    CONTRACT_VERSION, EvaluationOutcome, EvaluationReport, EvaluationRequest, EvaluationResult,
    Evaluator, Program, ProviderId, SourceLanguage,
};
use regorus::{Engine, Value, utils::limits::ExecutionTimerConfig};
use std::{num::NonZeroU32, time::Duration};

#[derive(Clone, Copy, Debug, Default)]
pub struct RegoEvaluator;

fn prepare(request: &EvaluationRequest) -> Result<Engine, String> {
    let Program::Source {
        language: SourceLanguage::Rego,
        modules,
    } = request.program();
    let mut engine = Engine::new();
    engine.set_strict_builtin_errors(true);
    // A policy's print builtin must never corrupt the host's JSON transport.
    engine.set_gather_prints(true);
    engine.set_execution_timer_config(ExecutionTimerConfig {
        limit: Duration::from_millis(request.timeout_ms()),
        check_interval: NonZeroU32::new(1).unwrap(),
    });
    for module in modules {
        engine
            .add_policy(module.path.clone(), module.source.clone())
            .map_err(|error| error.to_string())?;
    }
    engine
        .set_input_json(&request.input().to_string())
        .map_err(|error| error.to_string())?;
    Ok(engine)
}

fn evaluate_rule(engine: &mut Engine, entrypoint: &str) -> EvaluationOutcome {
    match engine.eval_rule(entrypoint.to_owned()) {
        Ok(Value::Undefined) => EvaluationOutcome::Undefined,
        Ok(value) => match serde_json::to_value(value) {
            Ok(value) => EvaluationOutcome::Value { value },
            Err(error) => EvaluationOutcome::Error {
                message: error.to_string(),
            },
        },
        Err(error) => EvaluationOutcome::Error {
            message: error.to_string(),
        },
    }
}

impl Evaluator for RegoEvaluator {
    fn provider(&self) -> ProviderId {
        ProviderId::Rego
    }

    fn evaluate(&self, request: &EvaluationRequest) -> EvaluationReport {
        let mut engine = prepare(request);
        let results = request
            .entrypoints()
            .iter()
            .map(|entrypoint| EvaluationResult {
                entrypoint: entrypoint.clone(),
                outcome: match &mut engine {
                    Ok(engine) => evaluate_rule(engine, entrypoint),
                    Err(message) => EvaluationOutcome::Error {
                        message: message.clone(),
                    },
                },
            })
            .collect();
        EvaluationReport {
            version: CONTRACT_VERSION,
            provider: self.provider(),
            results,
        }
    }
}
