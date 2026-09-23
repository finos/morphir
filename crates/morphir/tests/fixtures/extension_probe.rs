//! Small standalone MEP guest for install transaction tests.
use std::io::{self, BufRead, Read, Write};

fn main() {
    let protocol = env!("MEP_VERSION");
    let mode = std::env::args().nth(1).unwrap_or_default();
    let extension = r#"{"id":"morphir-test","name":"Morphir test frontend","version":"1.2.3","types":["frontend"]}"#;
    let capabilities = r#"{"frontend":{"languages":[{"id":"test","fileExtensions":[".test"]}],"irVersions":["4"],"compile":true,"incremental":false,"fragments":false}}"#;
    let capabilities = if mode.ends_with("disagree") {
        capabilities.replace("\"compile\":true", "\"compile\":false")
    } else {
        capabilities.to_owned()
    };
    let mut input = io::stdin().lock();
    loop {
        let mut length = 0;
        loop {
            let mut line = String::new();
            if input.read_line(&mut line).unwrap() == 0 {
                return;
            }
            if line == "\r\n" {
                break;
            }
            if let Some(value) = line.strip_prefix("Content-Length:") {
                length = value.trim().parse().unwrap();
            }
        }
        let mut body = vec![0; length];
        input.read_exact(&mut body).unwrap();
        let request = String::from_utf8(body).unwrap();
        let (id, payload) = if request.contains("morphir.extension.describe") {
            if mode == "fail" {
                return;
            }
            if mode.starts_with("fallback") {
                (
                    1,
                    r#""error":{"code":-32601,"message":"Method not found"}"#.to_owned(),
                )
            } else {
                (
                    1,
                    format!(
                        r#""result":{{"statementVersion":"0.1.0-draft.1","protocolVersions":["{protocol}"],"extension":{extension},"capabilities":{capabilities}}}"#
                    ),
                )
            }
        } else if request.contains("morphir.initialized") {
            continue;
        } else if request.contains("morphir.initialize") {
            (
                2,
                format!(
                    r#""result":{{"protocolVersion":"{protocol}","extension":{extension},"capabilities":{capabilities}}}"#
                ),
            )
        } else if request.contains("morphir.extension.capabilities") {
            (3, format!(r#""result":{capabilities}"#))
        } else if request.contains("morphir.shutdown") {
            (4, "\"result\":{}".into())
        } else if request.contains("morphir.exit") {
            return;
        } else {
            panic!("unexpected request: {request}");
        };
        let response = format!(r#"{{"jsonrpc":"2.0","id":{id},{payload}}}"#);
        print!("Content-Length: {}\r\n\r\n{}", response.len(), response);
        io::stdout().flush().unwrap();
    }
}
