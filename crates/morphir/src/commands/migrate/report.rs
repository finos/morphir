use serde::Serialize;

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct MigrateResult<'a> {
    success: bool,
    input: &'a str,
    output: &'a str,
    #[serde(skip_serializing_if = "Option::is_none")]
    source: Option<&'a str>,
    #[serde(skip_serializing_if = "Option::is_none")]
    target: Option<&'a str>,
    #[serde(skip_serializing_if = "warnings_empty")]
    warnings: &'a [String],
    #[serde(skip_serializing_if = "Option::is_none")]
    error: Option<&'a str>,
}

fn warnings_empty(value: &&[String]) -> bool {
    value.is_empty()
}

pub(super) fn error(json: bool, input: &str, output: &str, message: &str) {
    if json {
        let result = MigrateResult {
            success: false,
            input,
            output,
            source: None,
            target: None,
            warnings: &[],
            error: Some(message),
        };
        println!("{}", serde_json::to_string_pretty(&result).unwrap());
    } else {
        eprintln!("{message}");
    }
}

pub(super) fn success(
    json: bool,
    has_output: bool,
    input: &str,
    output: &str,
    source: &str,
    target: &str,
    warnings: &[String],
) {
    if json && has_output {
        let result = MigrateResult {
            success: true,
            input,
            output,
            source: Some(source),
            target: Some(target),
            warnings,
            error: None,
        };
        println!("{}", serde_json::to_string_pretty(&result).unwrap());
    } else {
        for warning in warnings {
            eprintln!("warning: {warning}");
        }
        if !json {
            eprintln!("Migration complete.");
        }
    }
}
