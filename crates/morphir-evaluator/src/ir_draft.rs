//! Draft V1 native Morphir IR evaluation contract. Numeric V1 Rego stays separate.

use morphir_core::ir::classic as ir;
use morphir_runtime::{EvaluationError, EvaluationLimits, RuntimeValue, evaluate_v3_with_deadline};
use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::collections::{HashMap, HashSet};
use std::time::{Duration, Instant};

pub const VERSION: &str = "1.1.0-draft.1";
pub const MAX_REQUEST_BYTES: usize = 8_388_608;
pub const MAX_JSON_DEPTH: usize = 64;

#[derive(Debug, Clone, PartialEq, Eq, thiserror::Error)]
#[error("{code}: {message}")]
pub struct IrRequestError {
    pub code: &'static str,
    pub message: String,
}

fn error(code: &'static str, message: impl Into<String>) -> IrRequestError {
    IrRequestError {
        code,
        message: message.into(),
    }
}

#[derive(Debug, Clone, Deserialize)]
#[serde(deny_unknown_fields)]
struct RequestWire {
    version: Value,
    provider: String,
    program: ProgramWire,
    calls: Vec<CallWire>,
    limits: LimitsWire,
    timeout_ms: u64,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(deny_unknown_fields)]
struct ProgramWire {
    kind: String,
    distribution: Value,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(deny_unknown_fields)]
struct CallWire {
    id: String,
    entrypoint: String,
    arguments: Vec<TypedWireValue>,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(deny_unknown_fields, rename_all = "camelCase")]
struct LimitsWire {
    fuel: u64,
    max_call_depth: usize,
}

#[derive(Debug, Clone, PartialEq, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub struct TypedWireValue {
    #[serde(rename = "type")]
    pub ty: ir::Type<ir::Attrs>,
    pub value: WireValue,
}

#[derive(Debug, Clone, PartialEq, Deserialize, Serialize)]
#[serde(tag = "kind", rename_all = "snake_case", deny_unknown_fields)]
pub enum WireValue {
    Unit,
    Boolean { value: bool },
    Integer { value: String },
    String { value: String },
    List { elements: Vec<Self> },
    Tuple { elements: Vec<Self> },
    Constructor { name: String, arguments: Vec<Self> },
}

#[derive(Debug, Clone)]
struct ValidCall {
    id: String,
    entrypoint: String,
    name: ir::FQName,
    arguments: Vec<RuntimeValue>,
    output_type: ir::Type<ir::Attrs>,
}

#[derive(Debug, Clone)]
pub struct IrEvaluationRequest {
    distribution: ir::Distribution,
    calls: Vec<ValidCall>,
    limits: EvaluationLimits,
    timeout_ms: u64,
}

#[derive(Debug, Clone, PartialEq, Deserialize, Serialize)]
pub struct IrEvaluationReport {
    pub version: String,
    pub provider: String,
    pub results: Vec<IrResult>,
}

#[derive(Debug, Clone, PartialEq, Deserialize, Serialize)]
pub struct IrResult {
    pub id: String,
    pub entrypoint: String,
    pub status: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub value: Option<TypedWireValue>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub code: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub message: Option<String>,
}

impl IrEvaluationReport {
    pub fn has_errors(&self) -> bool {
        self.results.iter().any(|result| result.status == "error")
    }
}

impl IrEvaluationRequest {
    pub fn from_slice(bytes: &[u8]) -> Result<Self, IrRequestError> {
        if bytes.len() > MAX_REQUEST_BYTES {
            return Err(error(
                "REQUEST_TOO_LARGE",
                "evaluation request exceeds 8,388,608 bytes",
            ));
        }
        let value: Value = serde_json::from_slice(bytes)
            .map_err(|e| error("INVALID_EVALUATION_REQUEST", e.to_string()))?;
        if json_depth(&value) > MAX_JSON_DEPTH {
            return Err(error(
                "REQUEST_TOO_DEEP",
                "evaluation request exceeds 64 JSON container levels",
            ));
        }
        Self::from_value(value)
    }

    pub fn from_value(value: Value) -> Result<Self, IrRequestError> {
        if value.get("version") != Some(&Value::String(VERSION.into())) {
            return Err(error(
                "UNSUPPORTED_EVALUATION_VERSION",
                "native IR evaluation requires 1.1.0-draft.1",
            ));
        }
        let wire: RequestWire = serde_json::from_value(value)
            .map_err(|e| error("INVALID_EVALUATION_REQUEST", e.to_string()))?;
        if wire.version != VERSION {
            return Err(error(
                "UNSUPPORTED_EVALUATION_VERSION",
                "unsupported evaluation version",
            ));
        }
        if wire.provider != "morphir_ir" || wire.program.kind != "morphir_ir" {
            return Err(error(
                "INVALID_IR_PROGRAM",
                "the draft native IR request requires matching provider and program kind",
            ));
        }
        if !(1..=300_000).contains(&wire.timeout_ms)
            || !(1..=1_000_000).contains(&wire.limits.fuel)
            || !(1..=1024).contains(&wire.limits.max_call_depth)
        {
            return Err(error(
                "INVALID_LIMITS",
                "timeout, fuel, or call depth is outside the draft bounds",
            ));
        }
        if !(1..=64).contains(&wire.calls.len()) {
            return Err(error(
                "INVALID_CALLS",
                "the draft request requires 1 to 64 calls",
            ));
        }
        let distribution: ir::Distribution = serde_json::from_value(wire.program.distribution)
            .map_err(|e| error("INVALID_IR_PROGRAM", e.to_string()))?;
        if distribution.format_version != 3 {
            return Err(error(
                "INVALID_IR_PROGRAM",
                "native evaluator requires classic IR formatVersion 3",
            ));
        }
        let mut ids = HashSet::new();
        let mut calls = Vec::with_capacity(wire.calls.len());
        for call in wire.calls {
            if call.id.trim().is_empty() || !ids.insert(call.id.clone()) {
                return Err(error(
                    "INVALID_CALLS",
                    "call IDs must be nonempty and unique",
                ));
            }
            let name = parse_name(&call.entrypoint)
                .map_err(|message| error("UNKNOWN_ENTRYPOINT", message))?;
            let definition = find_definition(&distribution, &name).ok_or_else(|| {
                error(
                    "UNKNOWN_ENTRYPOINT",
                    format!("unknown entrypoint {}", call.entrypoint),
                )
            })?;
            if call.arguments.len() != definition.input_types.len() {
                return Err(error(
                    "ARGUMENT_ARITY_MISMATCH",
                    format!(
                        "{} expects {} arguments, got {}",
                        call.entrypoint,
                        definition.input_types.len(),
                        call.arguments.len()
                    ),
                ));
            }
            if !supported_type(
                &distribution,
                &definition.output_type,
                &HashMap::new(),
                &mut HashSet::new(),
            ) {
                return Err(error(
                    "UNSUPPORTED_RETURN_CODEC",
                    format!(
                        "{} has an output type unsupported by the draft value codec",
                        call.entrypoint
                    ),
                ));
            }
            let mut arguments = Vec::with_capacity(call.arguments.len());
            for (parameter, argument) in definition.input_types.iter().zip(&call.arguments) {
                if !same_type(&parameter.ty, &argument.ty) {
                    return Err(error(
                        "ARGUMENT_TYPE_MISMATCH",
                        format!(
                            "{} argument {} has the wrong type",
                            call.entrypoint, parameter.name
                        ),
                    ));
                }
                arguments.push(decode_value(
                    &distribution,
                    &argument.ty,
                    &argument.value,
                    &HashMap::new(),
                )?);
            }
            calls.push(ValidCall {
                id: call.id,
                entrypoint: call.entrypoint,
                name,
                arguments,
                output_type: definition.output_type.clone(),
            });
        }
        validate_sdk(&distribution)?;
        Ok(Self {
            distribution,
            calls,
            limits: EvaluationLimits {
                fuel: wire.limits.fuel,
                max_call_depth: wire.limits.max_call_depth,
            },
            timeout_ms: wire.timeout_ms,
        })
    }

    pub fn timeout_ms(&self) -> u64 {
        self.timeout_ms
    }

    pub fn evaluate(&self) -> IrEvaluationReport {
        let deadline = Instant::now() + Duration::from_millis(self.timeout_ms);
        let results = self
            .calls
            .iter()
            .map(|call| {
                match evaluate_v3_with_deadline(
                    &self.distribution,
                    &call.name,
                    call.arguments.clone(),
                    self.limits,
                    Some(deadline),
                ) {
                    Ok(value) => match encode_value(
                        &self.distribution,
                        &call.output_type,
                        &value,
                        &HashMap::new(),
                    ) {
                        Ok(encoded) => IrResult {
                            id: call.id.clone(),
                            entrypoint: call.entrypoint.clone(),
                            status: "value".into(),
                            value: Some(TypedWireValue {
                                ty: call.output_type.clone(),
                                value: encoded,
                            }),
                            code: None,
                            message: None,
                        },
                        Err(message) => runtime_error(call, "VALUE_CODEC_ERROR", message),
                    },
                    Err(failure) => {
                        runtime_error(call, runtime_code(&failure), runtime_message(&failure))
                    }
                }
            })
            .collect();
        IrEvaluationReport {
            version: VERSION.into(),
            provider: "morphir_ir".into(),
            results,
        }
    }
}

fn runtime_error(call: &ValidCall, code: &str, message: String) -> IrResult {
    IrResult {
        id: call.id.clone(),
        entrypoint: call.entrypoint.clone(),
        status: "error".into(),
        value: None,
        code: Some(code.into()),
        message: Some(message),
    }
}

fn runtime_code(error: &EvaluationError) -> &'static str {
    match error {
        EvaluationError::FuelExhausted => "FUEL_EXHAUSTED",
        EvaluationError::DeadlineExceeded => "DEADLINE_EXCEEDED",
        EvaluationError::CallDepthExceeded => "CALL_DEPTH_EXCEEDED",
        EvaluationError::NonExhaustivePattern => "NON_EXHAUSTIVE_PATTERN",
        EvaluationError::IntegerOverflow => "INTEGER_OVERFLOW",
        EvaluationError::UnsupportedExpression(_) => "UNSUPPORTED_EXPRESSION",
        EvaluationError::MissingDependency(_) => "MISSING_DEPENDENCY",
        EvaluationError::ArityMismatch { .. } => "ARGUMENT_ARITY_MISMATCH",
        _ => "EVALUATION_ERROR",
    }
}

fn runtime_message(error: &EvaluationError) -> String {
    match error {
        EvaluationError::FuelExhausted => "Evaluation fuel exhausted".into(),
        EvaluationError::DeadlineExceeded => "Evaluation deadline exceeded".into(),
        EvaluationError::CallDepthExceeded => "Evaluation call depth exceeded".into(),
        EvaluationError::NonExhaustivePattern => "Non-exhaustive pattern match".into(),
        EvaluationError::IntegerOverflow => "Integer overflow".into(),
        EvaluationError::UnsupportedExpression(expression) => {
            format!("Unsupported expression: {expression}")
        }
        other => format!("{other:?}"),
    }
}

fn json_depth(value: &Value) -> usize {
    match value {
        Value::Array(items) => 1 + items.iter().map(json_depth).max().unwrap_or(0),
        Value::Object(items) => 1 + items.values().map(json_depth).max().unwrap_or(0),
        _ => 0,
    }
}

fn path(text: &str) -> ir::Path {
    ir::Path::new(text.split('/').map(ir::Name::from_str).collect())
}

fn parse_name(text: &str) -> Result<ir::FQName, String> {
    let parsed = morphir_core::naming::FQName::from_canonical_string(text)?;
    if parsed.to_canonical_string() != text
        || parsed.package_path.is_empty()
        || parsed.module_path.is_empty()
    {
        return Err(format!("noncanonical FQName: {text}"));
    }
    Ok(ir::FQName::new(
        path(&parsed.package_path.to_string()),
        path(&parsed.module_path.to_string()),
        ir::Name::from_str(&parsed.local_name.to_string()),
    ))
}

fn find_definition<'a>(
    distribution: &'a ir::Distribution,
    name: &ir::FQName,
) -> Option<&'a ir::ValueDefinition<ir::Attrs, ir::Type<ir::Attrs>>> {
    let ir::DistributionBody::Library(package, _, definition) = &distribution.distribution;
    if &name.package_path != package {
        return None;
    }
    definition
        .modules
        .iter()
        .find(|module| module.path == name.module_path)?
        .definition
        .value
        .values
        .iter()
        .find(|(local, _)| local == &name.local_name)
        .map(|(_, value)| &value.value.value)
}

fn same_type(left: &ir::Type<ir::Attrs>, right: &ir::Type<ir::Attrs>) -> bool {
    left == right
}

fn sdk_name(module: &str, local: &str) -> ir::FQName {
    ir::FQName::new(path("morphir/SDK"), path(module), ir::Name::from_str(local))
}

fn find_constructor<'a>(
    distribution: &'a ir::Distribution,
    type_name: &ir::FQName,
    name: &ir::FQName,
) -> Option<(&'a [ir::Name], &'a ir::Constructor<ir::Attrs>)> {
    let ir::DistributionBody::Library(package, _, definition) = &distribution.distribution;
    if &name.package_path != package
        || name.package_path != type_name.package_path
        || name.module_path != type_name.module_path
    {
        return None;
    }
    let module = definition
        .modules
        .iter()
        .find(|module| module.path == type_name.module_path)?;
    module
        .definition
        .value
        .types
        .iter()
        .find(|(local, _)| local == &type_name.local_name)
        .and_then(|(_, ty)| {
            let ir::TypeDefinition::Custom(params, constructors) = &ty.value.value else {
                return None;
            };
            constructors
                .value
                .iter()
                .find(|ctor| ctor.name == name.local_name)
                .map(|ctor| (params.as_slice(), ctor))
        })
}

fn supported_type(
    distribution: &ir::Distribution,
    ty: &ir::Type<ir::Attrs>,
    vars: &HashMap<ir::Name, ir::Type<ir::Attrs>>,
    seen: &mut HashSet<ir::FQName>,
) -> bool {
    match ty {
        ir::Type::Unit(_) => true,
        ir::Type::Variable(_, name) => vars
            .get(name)
            .is_some_and(|bound| supported_type(distribution, bound, vars, seen)),
        ir::Type::Tuple(_, elements) => elements
            .iter()
            .all(|element| supported_type(distribution, element, vars, seen)),
        ir::Type::Reference(_, name, arguments)
            if name == &sdk_name("basics", "int")
                || name == &sdk_name("basics", "bool")
                || name == &sdk_name("string", "string") =>
        {
            arguments.is_empty()
        }
        ir::Type::Reference(_, name, arguments) if name == &sdk_name("list", "list") => {
            arguments.len() == 1 && supported_type(distribution, &arguments[0], vars, seen)
        }
        ir::Type::Reference(_, name, arguments) => {
            if !seen.insert(name.clone()) {
                return true;
            }
            let ir::DistributionBody::Library(package, _, definition) = &distribution.distribution;
            if &name.package_path != package {
                return false;
            }
            let Some(module) = definition
                .modules
                .iter()
                .find(|module| module.path == name.module_path)
            else {
                return false;
            };
            let Some((_, controlled)) = module
                .definition
                .value
                .types
                .iter()
                .find(|(local, _)| local == &name.local_name)
            else {
                return false;
            };
            let ir::TypeDefinition::Custom(params, constructors) = &controlled.value.value else {
                return false;
            };
            if params.len() != arguments.len() {
                return false;
            }
            let bindings: HashMap<_, _> = params
                .iter()
                .cloned()
                .zip(arguments.iter().cloned())
                .collect();
            constructors.value.iter().all(|ctor| {
                ctor.args
                    .iter()
                    .all(|(_, field)| supported_type(distribution, field, &bindings, seen))
            })
        }
        _ => false,
    }
}

fn decode_value(
    distribution: &ir::Distribution,
    ty: &ir::Type<ir::Attrs>,
    wire: &WireValue,
    vars: &HashMap<ir::Name, ir::Type<ir::Attrs>>,
) -> Result<RuntimeValue, IrRequestError> {
    let failure = || {
        error(
            "VALUE_CODEC_ERROR",
            "tagged value does not match its Morphir type",
        )
    };
    match (ty, wire) {
        (ir::Type::Variable(_, name), _) => decode_value(
            distribution,
            vars.get(name).ok_or_else(failure)?,
            wire,
            vars,
        ),
        (ir::Type::Unit(_), WireValue::Unit) => Ok(RuntimeValue::Unit),
        (ir::Type::Reference(_, name, args), WireValue::Integer { value })
            if name == &sdk_name("basics", "int") && args.is_empty() =>
        {
            value
                .parse::<i64>()
                .map(RuntimeValue::Integer)
                .map_err(|_| failure())
        }
        (ir::Type::Reference(_, name, args), WireValue::Boolean { value })
            if name == &sdk_name("basics", "bool") && args.is_empty() =>
        {
            Ok(RuntimeValue::Boolean(*value))
        }
        (ir::Type::Reference(_, name, args), WireValue::String { value })
            if name == &sdk_name("string", "string") && args.is_empty() =>
        {
            Ok(RuntimeValue::String(value.clone()))
        }
        (ir::Type::Reference(_, name, args), WireValue::List { elements })
            if name == &sdk_name("list", "list") && args.len() == 1 =>
        {
            Ok(RuntimeValue::List(
                elements
                    .iter()
                    .map(|value| decode_value(distribution, &args[0], value, vars))
                    .collect::<Result<_, _>>()?,
            ))
        }
        (ir::Type::Tuple(_, types), WireValue::Tuple { elements })
            if types.len() == elements.len() =>
        {
            Ok(RuntimeValue::Tuple(
                types
                    .iter()
                    .zip(elements)
                    .map(|(ty, value)| decode_value(distribution, ty, value, vars))
                    .collect::<Result<_, _>>()?,
            ))
        }
        (
            ir::Type::Reference(_, type_name, type_args),
            WireValue::Constructor { name, arguments },
        ) => {
            let constructor_name = parse_name(name).map_err(|_| failure())?;
            if constructor_name.package_path != type_name.package_path
                || constructor_name.module_path != type_name.module_path
            {
                return Err(failure());
            }
            let (params, ctor) =
                find_constructor(distribution, type_name, &constructor_name).ok_or_else(failure)?;
            if params.len() != type_args.len() || ctor.args.len() != arguments.len() {
                return Err(failure());
            }
            let bindings: HashMap<_, _> = params
                .iter()
                .cloned()
                .zip(type_args.iter().cloned())
                .collect();
            let values = ctor
                .args
                .iter()
                .zip(arguments)
                .map(|((_, ty), value)| decode_value(distribution, ty, value, &bindings))
                .collect::<Result<_, _>>()?;
            Ok(RuntimeValue::Constructor(constructor_name, values))
        }
        _ => Err(failure()),
    }
}

fn encode_value(
    distribution: &ir::Distribution,
    ty: &ir::Type<ir::Attrs>,
    value: &RuntimeValue,
    vars: &HashMap<ir::Name, ir::Type<ir::Attrs>>,
) -> Result<WireValue, String> {
    match (ty, value) {
        (ir::Type::Variable(_, name), _) => encode_value(
            distribution,
            vars.get(name).ok_or("unbound type variable")?,
            value,
            vars,
        ),
        (ir::Type::Unit(_), RuntimeValue::Unit) => Ok(WireValue::Unit),
        (ir::Type::Reference(_, name, _), RuntimeValue::Integer(value))
            if name == &sdk_name("basics", "int") =>
        {
            Ok(WireValue::Integer {
                value: value.to_string(),
            })
        }
        (ir::Type::Reference(_, name, _), RuntimeValue::Boolean(value))
            if name == &sdk_name("basics", "bool") =>
        {
            Ok(WireValue::Boolean { value: *value })
        }
        (ir::Type::Reference(_, name, _), RuntimeValue::String(value))
            if name == &sdk_name("string", "string") =>
        {
            Ok(WireValue::String {
                value: value.clone(),
            })
        }
        (ir::Type::Reference(_, name, args), RuntimeValue::List(values))
            if name == &sdk_name("list", "list") && args.len() == 1 =>
        {
            Ok(WireValue::List {
                elements: values
                    .iter()
                    .map(|value| encode_value(distribution, &args[0], value, vars))
                    .collect::<Result<_, _>>()?,
            })
        }
        (ir::Type::Tuple(_, types), RuntimeValue::Tuple(values)) if types.len() == values.len() => {
            Ok(WireValue::Tuple {
                elements: types
                    .iter()
                    .zip(values)
                    .map(|(ty, value)| encode_value(distribution, ty, value, vars))
                    .collect::<Result<_, _>>()?,
            })
        }
        (ir::Type::Reference(_, type_name, type_args), RuntimeValue::Constructor(name, values))
            if name.package_path == type_name.package_path
                && name.module_path == type_name.module_path =>
        {
            let (params, ctor) = find_constructor(distribution, type_name, name)
                .ok_or("unknown result constructor")?;
            if params.len() != type_args.len() || ctor.args.len() != values.len() {
                return Err("result constructor arity mismatch".into());
            }
            let bindings: HashMap<_, _> = params
                .iter()
                .cloned()
                .zip(type_args.iter().cloned())
                .collect();
            Ok(WireValue::Constructor {
                name: canonical(name),
                arguments: ctor
                    .args
                    .iter()
                    .zip(values)
                    .map(|((_, ty), value)| encode_value(distribution, ty, value, &bindings))
                    .collect::<Result<_, _>>()?,
            })
        }
        _ => Err("result value does not match its declared type".into()),
    }
}

fn canonical(name: &ir::FQName) -> String {
    let render = |path: &ir::Path| {
        path.segments
            .iter()
            .map(ToString::to_string)
            .collect::<Vec<_>>()
            .join("/")
    };
    format!(
        "{}:{}#{}",
        render(&name.package_path),
        render(&name.module_path),
        name.local_name
    )
}

fn validate_sdk(distribution: &ir::Distribution) -> Result<(), IrRequestError> {
    let ir::DistributionBody::Library(package_name, dependencies, package) =
        &distribution.distribution;
    let sdk = path("morphir/SDK");
    let mut external = Vec::new();
    for (_, value) in package
        .modules
        .iter()
        .flat_map(|module| &module.definition.value.values)
    {
        collect_external_references(&value.value.value.body, package_name, &mut external);
    }
    for reference in external {
        let Some((_, dependency)) = dependencies
            .iter()
            .find(|(name, _)| name == &reference.package_path)
        else {
            return Err(error(
                "MISSING_DEPENDENCY",
                format!("missing specification for {}", canonical(&reference)),
            ));
        };
        if reference.package_path != sdk {
            return Err(error(
                "MISSING_DEPENDENCY",
                format!("no native implementation for {}", canonical(&reference)),
            ));
        }
        let expected_output = if reference == sdk_name("basics", "add") {
            sdk_name("basics", "int")
        } else if reference == sdk_name("basics", "equal") {
            sdk_name("basics", "bool")
        } else {
            return Err(error(
                "MISSING_DEPENDENCY",
                format!("unrecognized SDK value {}", canonical(&reference)),
            ));
        };
        let Some(specification) = dependency
            .modules
            .iter()
            .find(|module| module.path == reference.module_path)
            .and_then(|module| {
                module
                    .specification
                    .values
                    .iter()
                    .find(|(local, _)| local == &reference.local_name)
            })
            .map(|(_, documented)| &documented.value)
        else {
            return Err(error(
                "MISSING_DEPENDENCY",
                format!("missing SDK value specification {}", canonical(&reference)),
            ));
        };
        let int_type = ir::Type::Reference(ir::Attrs::None, sdk_name("basics", "int"), vec![]);
        let output_type = ir::Type::Reference(ir::Attrs::None, expected_output, vec![]);
        if specification.inputs.len() != 2
            || specification
                .inputs
                .iter()
                .any(|input| !same_type(&input.ty, &int_type))
            || !same_type(&specification.output, &output_type)
        {
            return Err(error(
                "MISSING_DEPENDENCY",
                format!("SDK signature mismatch for {}", canonical(&reference)),
            ));
        }
    }
    Ok(())
}

fn collect_external_references(
    value: &ir::Value<ir::Attrs, ir::Type<ir::Attrs>>,
    package: &ir::Path,
    references: &mut Vec<ir::FQName>,
) {
    match value {
        ir::Value::Reference(_, name) if &name.package_path != package => {
            references.push(name.clone())
        }
        ir::Value::Apply(_, function, argument) => {
            collect_external_references(function, package, references);
            collect_external_references(argument, package, references);
        }
        ir::Value::PatternMatch(_, subject, cases) => {
            collect_external_references(subject, package, references);
            for (_, body) in cases {
                collect_external_references(body, package, references);
            }
        }
        ir::Value::IfThenElse(_, condition, yes, no) => {
            for value in [condition.as_ref(), yes, no] {
                collect_external_references(value, package, references);
            }
        }
        ir::Value::List(_, values) | ir::Value::Tuple(_, values) => {
            for value in values {
                collect_external_references(value, package, references);
            }
        }
        ir::Value::Lambda(_, _, body) => collect_external_references(body, package, references),
        ir::Value::LetDefinition(_, _, definition, body) => {
            collect_external_references(&definition.body, package, references);
            collect_external_references(body, package, references);
        }
        ir::Value::LetRecursion(_, definitions, body) => {
            for (_, definition) in definitions {
                collect_external_references(&definition.body, package, references);
            }
            collect_external_references(body, package, references);
        }
        ir::Value::Destructure(_, _, bound, body) => {
            collect_external_references(bound, package, references);
            collect_external_references(body, package, references);
        }
        _ => {}
    }
}
