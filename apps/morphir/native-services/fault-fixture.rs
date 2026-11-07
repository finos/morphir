//! Native acceptance peer, using the shared framing library and a frozen guest.
//! It deliberately corrupts selected boundaries; it is never a production host.
use morphir_host_native::process::{read_frame, write_frame};
use serde_json::Value;
use std::{
    io::{Read, Write},
    process::Stdio,
    time::Duration,
};

/// The frozen guest, gzip-compressed, in one static so that the binary holds
/// one copy: `extension bundle` refuses artifacts above 11 MiB, and the Linux
/// release guest alone is about 9 MB. An inline `include_bytes!` is a
/// constant that codegen units may each copy.
static GUEST_GZIP: &[u8] = include_bytes!(env!("MORPHIR_TEST_GUEST_GZIP"));

#[tokio::main(flavor = "current_thread")]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let mode = args.first().map(String::as_str).unwrap_or("catalog");
    if let Some(pidfile) = args.get(1).filter(|_| mode != "operation-hang")
        && !pidfile.is_empty()
    {
        std::fs::write(pidfile, std::process::id().to_string())?;
    }
    match mode {
        // Both read the first request, so the host's write never races the
        // exit and the host sees the fault, not a closed pipe.
        "crash" | "malformed" => {
            read_frame(&mut tokio::io::BufReader::new(tokio::io::stdin())).await?;
            if mode == "crash" {
                std::process::exit(7);
            }
            print!("Content-Length: 3\r\n\r\n???");
            return Ok(());
        }
        "oversize" => {
            print!("Content-Length: 67108865\r\n\r\n");
            std::io::stdout().flush()?;
            tokio::time::sleep(Duration::from_secs(60)).await;
            return Ok(());
        }
        "hang" => {
            tokio::time::sleep(Duration::from_secs(60)).await;
            return Ok(());
        }
        _ => (),
    }
    let directory = tempfile::tempdir_in(std::env::current_exe()?.parent().unwrap())?;
    let guest = directory.path().join("guest");
    let mut bytes = Vec::new();
    flate2::read::GzDecoder::new(GUEST_GZIP).read_to_end(&mut bytes)?;
    std::fs::write(&guest, bytes)?;
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        std::fs::set_permissions(&guest, std::fs::Permissions::from_mode(0o500))?;
    }
    let mut child = tokio::process::Command::new(guest)
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::inherit())
        .kill_on_drop(true)
        .spawn()?;
    let mut input = child.stdin.take().unwrap();
    let mut output = tokio::io::BufReader::new(child.stdout.take().unwrap());
    let mut stdin = tokio::io::BufReader::new(tokio::io::stdin());
    let mut stdout = tokio::io::stdout();
    loop {
        let mut request: Value = serde_json::from_slice(&read_frame(&mut stdin).await?)?;
        if mode == "operation-hang" && request["method"] == "morphir.frontend.compileModel" {
            if let Some(pidfile) = args.get(1) {
                std::fs::write(pidfile, std::process::id().to_string())?;
                std::fs::write(format!("{pidfile}.args.json"), serde_json::to_vec(&args)?)?;
            }
            tokio::time::sleep(Duration::from_secs(60)).await;
            return Ok(());
        }
        if mode == "wrong-context" && request["method"] == "morphir.frontend.compileModel" {
            request["params"]["contextDigest"] = Value::String("invalid-context-digest".into());
        }
        write_frame(&mut input, &request).await?;
        if request.get("id").is_none() {
            if request["method"] == "morphir.exit" {
                drop(input);
                child.wait().await?;
                return Ok(());
            }
            continue;
        }
        let mut response: Value = serde_json::from_slice(&read_frame(&mut output).await?)?;
        if mode == "catalog" {
            let version = if env!("CARGO_BIN_NAME") == "native-catalog-v2" {
                "0.1.1"
            } else {
                "0.1.0"
            };
            if let Some(extension) = response["result"].get_mut("extension") {
                extension["version"] = Value::String(version.into());
            }
        }
        match (mode, request["method"].as_str().unwrap_or("")) {
            ("wrong-tuple", "morphir.initialize") => {
                response["result"]["capabilities"]["modelTransport"]["tuples"][0]["operation"] =
                    Value::String("morphir.backend.generateModel".into())
            }
            ("wrong-digest", "morphir.frontend.compileModel") => {
                response["result"]["model"]["payload"]["sha256"] = Value::String("0".repeat(64))
            }
            ("shutdown-hang", "morphir.shutdown") => {
                if let Some(pidfile) = args.get(1) {
                    std::fs::write(format!("{pidfile}.shutdown"), "")?;
                }
                tokio::time::sleep(Duration::from_secs(60)).await;
                return Ok(());
            }
            ("diagnostics", _) => eprintln!("native fixture diagnostic"),
            _ => (),
        }
        write_frame(&mut stdout, &response).await?;
    }
}
