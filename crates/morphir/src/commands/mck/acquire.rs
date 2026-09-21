//! Downloading the finos/morphir source archive for one commit, for
//! `kit vendor` and `kit update` with `--source github:finos/morphir`
//! (`spec/mck/kit-manifest.md`, "Sources and trust").
//!
//! One HTTPS request to the fixed host. Redirects stay on HTTPS GitHub hosts,
//! certificates are checked against the platform trust store with no way to
//! turn that off, proxies come from the standard environment variables, and
//! the body is streamed to a temporary file that may not exceed
//! `MAX_DOWNLOAD_BYTES`. Everything after the download (extraction, bounds,
//! unsafe entries, verification) is `morphir_mck::kit::archive`'s job.

use std::io::Write as _;
use std::time::Duration;

use morphir_mck::kit::archive::MAX_DOWNLOAD_BYTES;
use morphir_mck::kit::manifest::{CommitId, UPSTREAM_REPOSITORY};
use reqwest::Url;

/// The host GitHub serves commit archives from.
pub const ARCHIVE_HOST: &str = "codeload.github.com";
const MAX_REDIRECTS: usize = 5;

/// What `kit vendor` says about trust once per remote acquisition.
pub const TRUST_NOTE: &str = "note: the kit was fetched over TLS from GitHub for the commit you named. Its digests detect any later change; they do not prove who published it.";

/// The one URL an acquisition requests.
pub fn archive_url(revision: &CommitId) -> String {
    format!("https://{ARCHIVE_HOST}/{UPSTREAM_REPOSITORY}/tar.gz/{revision}")
}

/// Whether a redirect may be followed: HTTPS, on the default port, to
/// github.com or one of its subdomains.
pub fn redirect_allowed(url: &Url) -> bool {
    url.scheme() == "https"
        && url.port().is_none()
        && url
            .host_str()
            .is_some_and(|host| host == "github.com" || host.ends_with(".github.com"))
}

/// The running total after a chunk arrives, or the reason to stop.
fn add_within(total: u64, chunk: usize, limit: u64) -> Result<u64, String> {
    let total = total.saturating_add(chunk as u64);
    if total > limit {
        Err(format!(
            "the archive is larger than {limit} bytes; nothing was written"
        ))
    } else {
        Ok(total)
    }
}

/// Downloads the archive for `revision` into a temporary file, which is
/// removed when the returned handle is dropped.
pub async fn download(revision: &CommitId) -> Result<tempfile::NamedTempFile, String> {
    let client = reqwest::Client::builder()
        .https_only(true)
        .redirect(reqwest::redirect::Policy::custom(|attempt| {
            if attempt.previous().len() >= MAX_REDIRECTS {
                attempt.error(format!("more than {MAX_REDIRECTS} redirects"))
            } else if redirect_allowed(attempt.url()) {
                attempt.follow()
            } else {
                let refused = format!("refusing a redirect to {}", attempt.url());
                attempt.error(refused)
            }
        }))
        .connect_timeout(Duration::from_secs(30))
        .timeout(Duration::from_secs(600))
        .user_agent(concat!("morphir-cli/", env!("CARGO_PKG_VERSION")))
        .build()
        .map_err(|error| format!("cannot set up HTTPS: {error}"))?;

    let url = archive_url(revision);
    let response = client
        .get(&url)
        .send()
        .await
        .map_err(|error| format!("cannot fetch {url}: {error}"))?;
    let status = response.status();
    if !status.is_success() {
        return Err(format!(
            "GitHub answered {status} for {url}; is {revision} a commit of {UPSTREAM_REPOSITORY}?"
        ));
    }
    if let Some(length) = response.content_length() {
        add_within(
            0,
            usize::try_from(length).unwrap_or(usize::MAX),
            MAX_DOWNLOAD_BYTES,
        )?;
    }

    write_download(response, &url).await
}

async fn write_download(
    mut response: reqwest::Response,
    url: &str,
) -> Result<tempfile::NamedTempFile, String> {
    let mut file = tempfile::NamedTempFile::new()
        .map_err(|error| format!("cannot create a temporary file: {error}"))?;
    let mut total = 0;
    while let Some(chunk) = response
        .chunk()
        .await
        .map_err(|error| {
            if error.is_timeout() {
                format!("the download from {url} timed out after receiving {total} bytes; retry on a connection that can complete within the download deadline")
            } else {
                let causes = std::iter::successors(
                    Some(&error as &(dyn std::error::Error + 'static)),
                    |cause| cause.source(),
                )
                .map(ToString::to_string)
                .collect::<Vec<_>>()
                .join(": ");
                format!("the download from {url} failed after receiving {total} bytes: {causes}")
            }
        })?
    {
        total = add_within(total, chunk.len(), MAX_DOWNLOAD_BYTES)?;
        file.write_all(&chunk)
            .map_err(|error| format!("cannot write the download: {error}"))?;
    }
    file.flush()
        .map_err(|error| format!("cannot write the download: {error}"))?;
    Ok(file)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn url(text: &str) -> Url {
        Url::parse(text).unwrap()
    }

    fn read_request_headers(connection: &mut std::net::TcpStream) {
        use std::io::BufRead;
        for line in std::io::BufReader::new(connection).lines() {
            if line.unwrap().is_empty() {
                return;
            }
        }
        panic!("request ended before its headers were complete");
    }

    #[tokio::test]
    async fn a_truncated_download_preserves_the_non_timeout_cause() {
        use std::io::Write;
        let listener = std::net::TcpListener::bind("127.0.0.1:0").unwrap();
        let address = listener.local_addr().unwrap();
        let server = std::thread::spawn(move || {
            let (mut connection, _) = listener.accept().unwrap();
            read_request_headers(&mut connection);
            connection
                .write_all(b"HTTP/1.1 200 OK\r\nContent-Length: 6\r\n\r\nabc")
                .unwrap();
        });
        let endpoint = format!("http://{address}/archive");
        let response = reqwest::Client::builder()
            .no_proxy()
            .build()
            .unwrap()
            .get(&endpoint)
            .send()
            .await
            .unwrap();
        let error = write_download(response, &endpoint).await.unwrap_err();
        server.join().unwrap();
        assert!(error.contains("3 bytes"), "{error}");
        assert!(!error.contains("timed out"), "{error}");
        assert!(
            error.contains("error decoding response body: "),
            "missing underlying cause: {error}"
        );
    }

    #[tokio::test]
    async fn a_stalled_download_identifies_the_timeout_and_received_bytes() {
        use std::io::Write;
        let listener = std::net::TcpListener::bind("127.0.0.1:0").unwrap();
        let address = listener.local_addr().unwrap();
        let (finish, wait) = std::sync::mpsc::channel::<()>();
        let server = std::thread::spawn(move || {
            let (mut connection, _) = listener.accept().unwrap();
            read_request_headers(&mut connection);
            connection
                .write_all(b"HTTP/1.1 200 OK\r\nContent-Length: 6\r\n\r\nabc")
                .unwrap();
            let _ = wait.recv_timeout(Duration::from_secs(10));
        });
        let endpoint = format!("http://{address}/archive");
        let response = reqwest::Client::builder()
            .no_proxy()
            .read_timeout(Duration::from_millis(200))
            .build()
            .unwrap()
            .get(&endpoint)
            .send()
            .await
            .unwrap();
        let error = write_download(response, &endpoint).await.unwrap_err();
        let _ = finish.send(());
        server.join().unwrap();
        assert!(error.contains("timed out"), "{error}");
        assert!(error.contains("3 bytes"), "{error}");
    }

    #[test]
    fn the_request_names_the_fixed_host_repository_and_full_commit() {
        let revision = CommitId::parse("a2803f2cbfbb9baffe8a939e9462b18fd5bcdda0").unwrap();
        assert_eq!(
            archive_url(&revision),
            "https://codeload.github.com/finos/morphir/tar.gz/a2803f2cbfbb9baffe8a939e9462b18fd5bcdda0"
        );
        assert!(redirect_allowed(&url(&archive_url(&revision))));
    }

    #[test]
    fn redirects_stay_on_https_github_hosts() {
        for allowed in [
            "https://github.com/finos/morphir",
            "https://codeload.github.com/x",
            "https://objects.github.com/y",
        ] {
            assert!(redirect_allowed(&url(allowed)), "{allowed}");
        }
        for refused in [
            "http://codeload.github.com/x",
            "https://github.com.evil.example/x",
            "https://evilgithub.com/x",
            "https://codeload.github.com:8443/x",
            "https://example.com/x",
        ] {
            assert!(!redirect_allowed(&url(refused)), "{refused}");
        }
    }

    #[test]
    fn the_download_bound_is_inclusive_and_never_wraps() {
        assert_eq!(add_within(0, 10, 10), Ok(10));
        assert!(add_within(10, 1, 10).is_err());
        assert!(add_within(u64::MAX, 1, 10).is_err());
        assert!(add_within(0, usize::MAX, MAX_DOWNLOAD_BYTES).is_err());
    }
}
