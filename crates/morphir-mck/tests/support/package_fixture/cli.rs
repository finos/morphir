// Copyright 2026 FINOS
// SPDX-License-Identifier: Apache-2.0
use super::Result;
use std::{collections::BTreeMap, path::PathBuf};
#[derive(Debug, PartialEq, Eq)]
pub enum Destination {
    Check(PathBuf),
    Output(PathBuf),
}
#[derive(Debug)]
pub struct Arguments {
    pub source: PathBuf,
    pub destination: Destination,
}
pub fn parse_arguments(args: impl IntoIterator<Item = String>) -> Result<Arguments> {
    let mut args = args.into_iter();
    let mut options = BTreeMap::new();
    while let Some(key) = args.next() {
        let value = args
            .next()
            .ok_or("Expected explicit --source DIR and exactly one --check DIR or --output DIR")?;
        if !["--source", "--check", "--output"].contains(&key.as_str())
            || value.is_empty()
            || value.starts_with("--")
            || options.insert(key, value).is_some()
        {
            return Err(
                "Expected explicit --source DIR and exactly one --check DIR or --output DIR".into(),
            );
        }
    }
    let source = PathBuf::from(
        options
            .remove("--source")
            .ok_or("Explicit --source is required")?,
    );
    let destination = match (options.remove("--check"), options.remove("--output")) {
        (Some(path), None) => Destination::Check(path.into()),
        (None, Some(path)) => Destination::Output(path.into()),
        _ => return Err("Exactly one --check or --output is required".into()),
    };
    Ok(Arguments {
        source,
        destination,
    })
}
