//! Compatibility entry point for Morphir-defined decorator values.
//!
//! The shared core validates closed JSON data. This module keeps the sidecar
//! entryPoint spelling and construction-time existence check.

use morphir_core::data_value::{DataValueError, DataValueValidator};
use morphir_core::ir::{classic, v4};
use morphir_core::naming::FQName;
use serde_json::Value;

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

fn core_error(failure: DataValueError) -> ValueTypeError {
    let message = failure
        .message
        .strip_prefix("duplicate data type ")
        .map(|name| format!("duplicate decoration type {name}"))
        .unwrap_or(failure.message);
    ValueTypeError {
        path: failure.path,
        message,
    }
}

/// Validates sidecar JSON against one configured Morphir type entry point.
pub struct ValueValidator {
    entry_point: FQName,
    validator: DataValueValidator,
}

impl ValueValidator {
    pub fn entry_point(&self) -> &FQName {
        &self.entry_point
    }

    pub fn v3(
        distribution: &classic::Distribution,
        entry_point: &str,
    ) -> Result<Self, ValueTypeError> {
        if distribution.format_version != 3 {
            return Err(error("$", "decoration type IR must be V3"));
        }
        let validator = DataValueValidator::v3(distribution).map_err(core_error)?;
        let entry_point = normalize_entry_point(entry_point)?;
        if !v3_contains(distribution, &entry_point) {
            return Err(error(
                "$",
                format!("decoration entryPoint {entry_point} is absent from its IR"),
            ));
        }
        Ok(Self {
            entry_point: FQName::from_canonical_string(&entry_point)
                .map_err(|message| error("$", message))?,
            validator,
        })
    }

    pub fn v4(distribution: &v4::Distribution, entry_point: &str) -> Result<Self, ValueTypeError> {
        let validator = DataValueValidator::v4(distribution).map_err(core_error)?;
        let entry_point = normalize_entry_point(entry_point)?;
        if !v4_contains(distribution, &entry_point) {
            return Err(error(
                "$",
                format!("decoration entryPoint {entry_point} is absent from its IR"),
            ));
        }
        Ok(Self {
            entry_point: FQName::from_canonical_string(&entry_point)
                .map_err(|message| error("$", message))?,
            validator,
        })
    }

    pub fn validate(&self, value: &Value) -> Result<(), ValueTypeError> {
        self.validator
            .validate_reference(&self.entry_point, value)
            .map_err(core_error)
    }
}

fn normalize_entry_point(text: &str) -> Result<String, ValueTypeError> {
    if text.contains('#') {
        return FQName::from_canonical_string(text)
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

fn v3_contains(distribution: &classic::Distribution, entry_point: &str) -> bool {
    match &distribution.distribution {
        classic::DistributionBody::Library(package, dependencies, definition) => {
            v3_definitions_contain(&classic_path(package), definition, entry_point)
                || dependencies.iter().any(|(package, spec)| {
                    v3_specifications_contain(&classic_path(package), spec, entry_point)
                })
        }
        classic::DistributionBody::Specs(package, dependencies, spec) => {
            v3_specifications_contain(&classic_path(package), spec, entry_point)
                || dependencies.iter().any(|(package, spec)| {
                    v3_specifications_contain(&classic_path(package), spec, entry_point)
                })
        }
    }
}

fn v3_definitions_contain(
    package: &str,
    definition: &classic::PackageDefinition<classic::Attrs, classic::Type<classic::Attrs>>,
    entry_point: &str,
) -> bool {
    definition.modules.iter().any(|entry| {
        let module = classic_path(&entry.path);
        entry
            .definition
            .value
            .types
            .iter()
            .any(|(name, _)| format!("{package}:{module}#{name}") == entry_point)
    })
}

fn v3_specifications_contain(
    package: &str,
    specification: &classic::PackageSpecification<classic::Attrs>,
    entry_point: &str,
) -> bool {
    specification.modules.iter().any(|entry| {
        let module = classic_path(&entry.path);
        entry
            .specification
            .types
            .iter()
            .any(|(name, _)| format!("{package}:{module}#{name}") == entry_point)
    })
}

fn v4_contains(distribution: &v4::Distribution, entry_point: &str) -> bool {
    match distribution {
        v4::Distribution::Library(library) => {
            v4_definitions_contain(
                &library.package_name.to_canonical_string(),
                &library.def,
                entry_point,
            ) || library
                .dependencies
                .iter()
                .any(|(package, spec)| v4_specifications_contain(package, spec, entry_point))
        }
        v4::Distribution::Specs(specs) => {
            v4_specifications_contain(
                &specs.package_name.to_canonical_string(),
                &specs.spec,
                entry_point,
            ) || specs
                .dependencies
                .iter()
                .any(|(package, spec)| v4_specifications_contain(package, spec, entry_point))
        }
        v4::Distribution::Application(application) => {
            v4_definitions_contain(
                &application.package_name.to_canonical_string(),
                &application.def,
                entry_point,
            ) || application
                .dependencies
                .iter()
                .any(|(package, def)| v4_definitions_contain(package, def, entry_point))
        }
    }
}

fn v4_definitions_contain(
    package: &str,
    definition: &v4::PackageDefinition,
    entry_point: &str,
) -> bool {
    definition.modules.iter().any(|(module, controlled)| {
        controlled
            .value
            .types
            .keys()
            .any(|name| format!("{package}:{module}#{name}") == entry_point)
    })
}

fn v4_specifications_contain(
    package: &str,
    specification: &v4::PackageSpecification,
    entry_point: &str,
) -> bool {
    specification.modules.iter().any(|(module, spec)| {
        spec.types
            .keys()
            .any(|name| format!("{package}:{module}#{name}") == entry_point)
    })
}
