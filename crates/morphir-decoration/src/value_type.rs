//! Morphir-defined JSON values used by decorator sidecars.
//!
//! The first draft accepts the concrete data shapes the Elm decoration codec
//! uses: primitives, lists, optional values, records, tuples, aliases and
//! custom constructors. Incomplete, opaque, derived and function types fail
//! explicitly; a caller never treats an unvalidated value as decoration data.

use morphir_core::ir::{classic, v4};
use morphir_core::naming::Name;
use serde_json::Value;
use std::collections::HashMap;

#[derive(Debug, Clone, PartialEq, Eq, thiserror::Error)]
#[error("{message} at {path}")]
pub struct ValueTypeError {
    pub path: String,
    pub message: String,
}

fn error(path: &str, message: impl Into<String>) -> ValueTypeError {
    ValueTypeError {
        path: path.to_owned(),
        message: message.into(),
    }
}

#[derive(Clone)]
enum TypeExpr {
    Unit,
    Variable(String),
    Reference(String, Vec<Self>),
    Record(Vec<(String, Self)>),
    Tuple(Vec<Self>),
    Unsupported(&'static str),
}

#[derive(Clone)]
enum TypeDefinition {
    Alias {
        params: Vec<String>,
        body: TypeExpr,
    },
    Custom {
        params: Vec<String>,
        constructors: HashMap<String, Vec<TypeExpr>>,
    },
    Unsupported(&'static str),
}

/// Validates sidecar JSON against one configured Morphir type entry point.
pub struct ValueValidator {
    entry_point: String,
    definitions: HashMap<String, TypeDefinition>,
}

impl ValueValidator {
    pub fn v3(
        distribution: &classic::Distribution,
        entry_point: &str,
    ) -> Result<Self, ValueTypeError> {
        if distribution.format_version != 3 {
            return Err(error("$", "decoration type IR must be V3"));
        }
        let classic::DistributionBody::Library(package, dependencies, definition) =
            &distribution.distribution;
        let mut definitions = HashMap::new();
        collect_v3_definitions(&mut definitions, &classic_path(package), definition)?;
        for (package, specification) in dependencies {
            collect_v3_specifications(&mut definitions, &classic_path(package), specification)?;
        }
        Self::new(entry_point, definitions)
    }

    pub fn v4(distribution: &v4::Distribution, entry_point: &str) -> Result<Self, ValueTypeError> {
        let mut definitions = HashMap::new();
        match distribution {
            v4::Distribution::Library(library) => {
                collect_v4_definitions(
                    &mut definitions,
                    &library.package_name.to_canonical_string(),
                    &library.def,
                )?;
                for (package, spec) in &library.dependencies {
                    collect_v4_specifications(&mut definitions, package, spec)?;
                }
            }
            v4::Distribution::Specs(specs) => {
                collect_v4_specifications(
                    &mut definitions,
                    &specs.package_name.to_canonical_string(),
                    &specs.spec,
                )?;
                for (package, spec) in &specs.dependencies {
                    collect_v4_specifications(&mut definitions, package, spec)?;
                }
            }
            v4::Distribution::Application(application) => {
                collect_v4_definitions(
                    &mut definitions,
                    &application.package_name.to_canonical_string(),
                    &application.def,
                )?;
                for (package, def) in &application.dependencies {
                    collect_v4_definitions(&mut definitions, package, def)?;
                }
            }
        }
        Self::new(entry_point, definitions)
    }

    fn new(
        entry_point: &str,
        definitions: HashMap<String, TypeDefinition>,
    ) -> Result<Self, ValueTypeError> {
        let entry_point = normalize_entry_point(entry_point)?;
        if !definitions.contains_key(&entry_point) {
            return Err(error(
                "$",
                format!("decoration entryPoint {entry_point} is absent from its IR"),
            ));
        }
        Ok(Self {
            entry_point,
            definitions,
        })
    }

    pub fn validate(&self, value: &Value) -> Result<(), ValueTypeError> {
        self.validate_type(
            &TypeExpr::Reference(self.entry_point.clone(), vec![]),
            value,
            &HashMap::new(),
            "$",
            0,
        )
    }

    fn validate_type(
        &self,
        ty: &TypeExpr,
        value: &Value,
        vars: &HashMap<String, TypeExpr>,
        path: &str,
        depth: usize,
    ) -> Result<(), ValueTypeError> {
        if depth > 128 {
            return Err(error(path, "decoration type/value nesting exceeds 128"));
        }
        let next = depth + 1;
        match ty {
            TypeExpr::Unit if value.is_null() => Ok(()),
            TypeExpr::Unit => Err(error(path, "expected unit (null)")),
            TypeExpr::Variable(name) => {
                let bound = vars
                    .get(name)
                    .ok_or_else(|| error(path, format!("unbound type variable {name}")))?;
                self.validate_type(bound, value, vars, path, next)
            }
            TypeExpr::Reference(name, args) => {
                if let Some((module, local)) = sdk_type(name) {
                    match (module, local) {
                        ("basics", "bool") if args.is_empty() && value.is_boolean() => {
                            return Ok(());
                        }
                        ("basics", "int") if args.is_empty() && value.as_i64().is_some() => {
                            return Ok(());
                        }
                        ("basics", "float") if args.is_empty() && value.is_number() => {
                            return Ok(());
                        }
                        ("string", "string") if args.is_empty() && value.is_string() => {
                            return Ok(());
                        }
                        ("char", "char")
                            if args.is_empty()
                                && value.as_str().is_some_and(|text| text.chars().count() == 1) =>
                        {
                            return Ok(());
                        }
                        ("decimal", "decimal")
                            if args.is_empty()
                                && value
                                    .as_str()
                                    .is_some_and(morphir_core::ir::decimal::is_decimal_lexeme) =>
                        {
                            return Ok(());
                        }
                        ("list", "list") if args.len() == 1 => {
                            let items = value
                                .as_array()
                                .ok_or_else(|| error(path, "expected list"))?;
                            for (index, item) in items.iter().enumerate() {
                                self.validate_type(
                                    &args[0],
                                    item,
                                    vars,
                                    &format!("{path}[{index}]"),
                                    next,
                                )?;
                            }
                            return Ok(());
                        }
                        ("maybe", "maybe") if args.len() == 1 => {
                            if value.is_null() {
                                return Ok(());
                            }
                            return self.validate_type(&args[0], value, vars, path, next);
                        }
                        _ => {
                            return Err(error(
                                path,
                                format!("value does not match SDK type {name}"),
                            ));
                        }
                    }
                }
                let definition = self.definitions.get(name).ok_or_else(|| {
                    error(
                        path,
                        format!("referenced Morphir type {name} is unavailable"),
                    )
                })?;
                match definition {
                    TypeDefinition::Alias { params, body } => {
                        let bindings = bind_type_args(params, args, vars, path)?;
                        self.validate_type(body, value, &bindings, path, next)
                    }
                    TypeDefinition::Custom {
                        params,
                        constructors,
                    } => {
                        let bindings = bind_type_args(params, args, vars, path)?;
                        let items = value
                            .as_array()
                            .ok_or_else(|| error(path, "expected constructor array"))?;
                        let tag = items
                            .first()
                            .and_then(Value::as_str)
                            .ok_or_else(|| error(path, "constructor array needs a string tag"))?;
                        let fields = constructors.get(tag).ok_or_else(|| {
                            error(path, format!("unknown constructor {tag} for {name}"))
                        })?;
                        if fields.len() + 1 != items.len() {
                            return Err(error(
                                path,
                                format!("constructor {tag} expects {} arguments", fields.len()),
                            ));
                        }
                        for (index, (field_type, field_value)) in
                            fields.iter().zip(&items[1..]).enumerate()
                        {
                            self.validate_type(
                                field_type,
                                field_value,
                                &bindings,
                                &format!("{path}[{}]", index + 1),
                                next,
                            )?;
                        }
                        Ok(())
                    }
                    TypeDefinition::Unsupported(kind) => Err(error(
                        path,
                        format!("{kind} is not a supported decoration value type"),
                    )),
                }
            }
            TypeExpr::Record(fields) => {
                let members = value
                    .as_object()
                    .ok_or_else(|| error(path, "expected record object"))?;
                for (name, field_type) in fields {
                    let field = members
                        .get(name)
                        .ok_or_else(|| error(path, format!("missing field {name}")))?;
                    self.validate_type(field_type, field, vars, &format!("{path}.{name}"), next)?;
                }
                if members.len() != fields.len() {
                    return Err(error(path, "record has unknown fields"));
                }
                Ok(())
            }
            TypeExpr::Tuple(elements) => {
                let items = value
                    .as_array()
                    .ok_or_else(|| error(path, "expected tuple array"))?;
                if items.len() != elements.len() {
                    return Err(error(
                        path,
                        format!("tuple expects {} elements", elements.len()),
                    ));
                }
                for (index, (item_type, item)) in elements.iter().zip(items).enumerate() {
                    self.validate_type(item_type, item, vars, &format!("{path}[{index}]"), next)?;
                }
                Ok(())
            }
            TypeExpr::Unsupported(kind) => Err(error(
                path,
                format!("{kind} is not a supported decoration value type"),
            )),
        }
    }
}

fn bind_type_args(
    params: &[String],
    args: &[TypeExpr],
    outer: &HashMap<String, TypeExpr>,
    path: &str,
) -> Result<HashMap<String, TypeExpr>, ValueTypeError> {
    if params.len() != args.len() {
        return Err(error(
            path,
            format!("type expects {} arguments", params.len()),
        ));
    }
    let mut bound = outer.clone();
    bound.extend(params.iter().cloned().zip(args.iter().cloned()));
    Ok(bound)
}

fn sdk_type(name: &str) -> Option<(&str, &str)> {
    let (package, rest) = name.split_once(':')?;
    if package != "morphir/SDK" && package != "morphir/s-d-k" {
        return None;
    }
    rest.split_once('#')
}

fn normalize_entry_point(text: &str) -> Result<String, ValueTypeError> {
    if text.contains('#') {
        return morphir_core::naming::FQName::from_canonical_string(text)
            .map(|name| name.to_canonical_string())
            .map_err(|message| error("$", message));
    }
    let parts = text.split(':').collect::<Vec<_>>();
    if parts.len() != 3 || parts.iter().any(|part| part.is_empty()) {
        return Err(error(
            "$",
            "entryPoint must name package:module:type or package:module#type",
        ));
    }
    let path = |text: &str| {
        text.split('.')
            .map(|segment| classic::Name::from_str(segment).to_string())
            .collect::<Vec<_>>()
            .join("/")
    };
    Ok(format!(
        "{}:{}#{}",
        path(parts[0]),
        path(parts[1]),
        classic::Name::from_str(parts[2])
    ))
}

fn classic_path(path: &classic::Path) -> String {
    path.segments
        .iter()
        .map(ToString::to_string)
        .collect::<Vec<_>>()
        .join("/")
}

fn classic_fq(name: &classic::FQName) -> String {
    format!(
        "{}:{}#{}",
        classic_path(&name.package_path),
        classic_path(&name.module_path),
        name.local_name
    )
}

fn v3_type(ty: &classic::Type<classic::Attrs>) -> TypeExpr {
    match ty {
        classic::Type::Unit(_) => TypeExpr::Unit,
        classic::Type::Variable(_, name) => TypeExpr::Variable(name.to_string()),
        classic::Type::Reference(_, name, args) => {
            TypeExpr::Reference(classic_fq(name), args.iter().map(v3_type).collect())
        }
        classic::Type::Record(_, fields) => TypeExpr::Record(
            fields
                .iter()
                .map(|field| (camel(&field.name.to_string()), v3_type(&field.ty)))
                .collect(),
        ),
        classic::Type::Tuple(_, elements) => {
            TypeExpr::Tuple(elements.iter().map(v3_type).collect())
        }
        classic::Type::ExtensibleRecord(_, _, _) => TypeExpr::Unsupported("extensible record"),
        classic::Type::Function(_, _, _) => TypeExpr::Unsupported("function"),
    }
}

fn v4_type(ty: &v4::Type) -> TypeExpr {
    match ty {
        v4::Type::Unit(_) => TypeExpr::Unit,
        v4::Type::Variable(_, name) => TypeExpr::Variable(name.to_canonical_string()),
        v4::Type::Reference(_, name, args) => TypeExpr::Reference(
            name.to_canonical_string(),
            args.iter().map(v4_type).collect(),
        ),
        v4::Type::Record(_, fields) => TypeExpr::Record(
            fields
                .iter()
                .map(|field| (field.name.to_camel_case(), v4_type(&field.tpe)))
                .collect(),
        ),
        v4::Type::Tuple(_, elements) => TypeExpr::Tuple(elements.iter().map(v4_type).collect()),
        v4::Type::ExtensibleRecord(_, _, _) => TypeExpr::Unsupported("extensible record"),
        v4::Type::Function(_, _, _) => TypeExpr::Unsupported("function"),
    }
}

fn camel(canonical: &str) -> String {
    Name::from_canonical_string(canonical)
        .expect("classic name normalized")
        .to_camel_case()
}

fn v3_definition(definition: &classic::TypeDefinition<classic::Attrs>) -> TypeDefinition {
    match definition {
        classic::TypeDefinition::Alias(params, body) => TypeDefinition::Alias {
            params: params.iter().map(ToString::to_string).collect(),
            body: v3_type(body),
        },
        classic::TypeDefinition::Custom(params, constructors) => TypeDefinition::Custom {
            params: params.iter().map(ToString::to_string).collect(),
            constructors: constructors
                .value
                .iter()
                .map(|constructor| {
                    (
                        camel(&constructor.name.to_string()),
                        constructor.args.iter().map(|(_, ty)| v3_type(ty)).collect(),
                    )
                })
                .collect(),
        },
    }
}

fn v3_specification(specification: &classic::TypeSpecification<classic::Attrs>) -> TypeDefinition {
    match specification {
        classic::TypeSpecification::Alias(params, body) => TypeDefinition::Alias {
            params: params.iter().map(ToString::to_string).collect(),
            body: v3_type(body),
        },
        classic::TypeSpecification::Custom(params, constructors) => TypeDefinition::Custom {
            params: params.iter().map(ToString::to_string).collect(),
            constructors: constructors
                .iter()
                .map(|constructor| {
                    (
                        camel(&constructor.name.to_string()),
                        constructor.args.iter().map(|(_, ty)| v3_type(ty)).collect(),
                    )
                })
                .collect(),
        },
        classic::TypeSpecification::Opaque(_) => TypeDefinition::Unsupported("opaque type"),
        classic::TypeSpecification::Derived(_, _) => TypeDefinition::Unsupported("derived type"),
    }
}

fn v4_definition(definition: &v4::TypeDefinition) -> TypeDefinition {
    match definition {
        v4::TypeDefinition::TypeAliasDefinition {
            type_params,
            type_expr,
        } => TypeDefinition::Alias {
            params: type_params.iter().map(Name::to_canonical_string).collect(),
            body: v4_type(type_expr),
        },
        v4::TypeDefinition::CustomTypeDefinition {
            type_params,
            constructors,
        } => TypeDefinition::Custom {
            params: type_params.iter().map(Name::to_canonical_string).collect(),
            constructors: constructors
                .value
                .iter()
                .map(|constructor| {
                    (
                        constructor.name.to_camel_case(),
                        constructor
                            .args
                            .iter()
                            .map(|arg| v4_type(&arg.arg_type))
                            .collect(),
                    )
                })
                .collect(),
        },
        v4::TypeDefinition::IncompleteTypeDefinition { .. } => {
            TypeDefinition::Unsupported("incomplete type")
        }
    }
}

fn v4_specification(specification: &v4::TypeSpecification) -> TypeDefinition {
    match specification {
        v4::TypeSpecification::TypeAliasSpecification {
            type_params,
            type_expr,
            ..
        } => TypeDefinition::Alias {
            params: type_params.iter().map(Name::to_canonical_string).collect(),
            body: v4_type(type_expr),
        },
        v4::TypeSpecification::CustomTypeSpecification {
            type_params,
            constructors,
            ..
        } => TypeDefinition::Custom {
            params: type_params.iter().map(Name::to_canonical_string).collect(),
            constructors: constructors
                .iter()
                .map(|constructor| {
                    (
                        constructor.name.to_camel_case(),
                        constructor
                            .args
                            .iter()
                            .map(|arg| v4_type(&arg.arg_type))
                            .collect(),
                    )
                })
                .collect(),
        },
        v4::TypeSpecification::OpaqueTypeSpecification { .. } => {
            TypeDefinition::Unsupported("opaque type")
        }
        v4::TypeSpecification::DerivedTypeSpecification { .. } => {
            TypeDefinition::Unsupported("derived type")
        }
    }
}

fn collect_v3_definitions(
    output: &mut HashMap<String, TypeDefinition>,
    package: &str,
    definition: &classic::PackageDefinition<classic::Attrs, classic::Type<classic::Attrs>>,
) -> Result<(), ValueTypeError> {
    for entry in &definition.modules {
        let module = classic_path(&entry.path);
        for (name, controlled) in &entry.definition.value.types {
            let key = format!("{package}:{module}#{name}");
            if output
                .insert(key.clone(), v3_definition(&controlled.value.value))
                .is_some()
            {
                return Err(error("$", format!("duplicate decoration type {key}")));
            }
        }
    }
    Ok(())
}

fn collect_v3_specifications(
    output: &mut HashMap<String, TypeDefinition>,
    package: &str,
    specification: &classic::PackageSpecification<classic::Attrs>,
) -> Result<(), ValueTypeError> {
    for entry in &specification.modules {
        let module = classic_path(&entry.path);
        for (name, documented) in &entry.specification.types {
            let key = format!("{package}:{module}#{name}");
            if output
                .insert(key.clone(), v3_specification(&documented.value))
                .is_some()
            {
                return Err(error("$", format!("duplicate decoration type {key}")));
            }
        }
    }
    Ok(())
}

fn collect_v4_definitions(
    output: &mut HashMap<String, TypeDefinition>,
    package: &str,
    definition: &v4::PackageDefinition,
) -> Result<(), ValueTypeError> {
    for (module, controlled) in &definition.modules {
        for (name, ty) in &controlled.value.types {
            let key = format!("{package}:{module}#{name}");
            if output
                .insert(key.clone(), v4_definition(&ty.value.value))
                .is_some()
            {
                return Err(error("$", format!("duplicate decoration type {key}")));
            }
        }
    }
    Ok(())
}

fn collect_v4_specifications(
    output: &mut HashMap<String, TypeDefinition>,
    package: &str,
    specification: &v4::PackageSpecification,
) -> Result<(), ValueTypeError> {
    for (module, spec) in &specification.modules {
        for (name, ty) in &spec.types {
            let key = format!("{package}:{module}#{name}");
            if output
                .insert(key.clone(), v4_specification(&ty.value))
                .is_some()
            {
                return Err(error("$", format!("duplicate decoration type {key}")));
            }
        }
    }
    Ok(())
}
