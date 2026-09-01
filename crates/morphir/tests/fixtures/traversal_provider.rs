use std::io::{self, BufRead, BufReader, Read, Write};

fn main() -> io::Result<()> {
    let stdin = io::stdin();
    let stdout = io::stdout();
    let mut reader = BufReader::new(stdin.lock());
    let mut writer = stdout.lock();

    while let Some(request) = receive(&mut reader)? {
        if request.contains(r#""method":"morphir.exit""#) {
            return Ok(());
        }
        let Some(id) = request_id(&request) else {
            continue;
        };
        let result = if request.contains(r#""method":"morphir.initialize""#) {
            r#"{"protocolVersion":"0.1","extension":{"id":"traversal-provider","name":"Traversal Provider","version":"1.0.0","types":["backend"]},"capabilities":{"backend":{"targets":["unsafe-test"],"irVersions":["4"],"generate":true}}}"#
        } else if request.contains(r#""method":"morphir.backend.generate""#) {
            r#"{"success":true,"artifacts":[{"path":"../escape.avsc","content":"{}","binary":false}],"diagnostics":[]}"#
        } else if request.contains(r#""method":"morphir.shutdown""#) {
            r#"{}"#
        } else {
            r#"{"code":-32601,"message":"method not found"}"#
        };
        send(&mut writer, &id, result)?;
    }

    Ok(())
}

fn receive(reader: &mut impl BufRead) -> io::Result<Option<String>> {
    let mut content_length = None;
    let mut line = String::new();
    loop {
        line.clear();
        if reader.read_line(&mut line)? == 0 {
            return Ok(None);
        }
        if line.trim_end().is_empty() {
            break;
        }
        let Some((name, value)) = line.split_once(':') else {
            return Err(io::Error::new(
                io::ErrorKind::InvalidData,
                "malformed MEP header",
            ));
        };
        if name.eq_ignore_ascii_case("content-length") {
            content_length = Some(
                value
                    .trim()
                    .parse::<usize>()
                    .map_err(|error| io::Error::new(io::ErrorKind::InvalidData, error))?,
            );
        }
    }

    let length = content_length.ok_or_else(|| {
        io::Error::new(io::ErrorKind::InvalidData, "missing Content-Length header")
    })?;
    let mut body = vec![0; length];
    reader.read_exact(&mut body)?;
    String::from_utf8(body)
        .map(Some)
        .map_err(|error| io::Error::new(io::ErrorKind::InvalidData, error))
}

fn request_id(request: &str) -> Option<String> {
    // `ExtensionRequest` serializes its top-level request ID after `params`.
    // Morphir IR can itself contain many `id` fields, so select the last key.
    let after_name = request.rsplit_once(r#""id""#)?.1;
    let value = after_name.split_once(':')?.1.trim_start();
    let end = value
        .find(|character: char| character == ',' || character == '}' || character.is_whitespace())
        .unwrap_or(value.len());
    Some(value[..end].to_owned())
}

fn send(writer: &mut impl Write, id: &str, result: &str) -> io::Result<()> {
    let body = format!(r#"{{"jsonrpc":"2.0","id":{id},"result":{result}}}"#);
    write!(writer, "Content-Length: {}\r\n\r\n{body}", body.len())?;
    writer.flush()
}
