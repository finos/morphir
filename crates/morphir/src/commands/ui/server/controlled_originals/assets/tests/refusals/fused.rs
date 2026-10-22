//! Fused-host component controls; no actual browser or profile verdict.
#[path = "fused/entry.rs"]
mod entry;
use super::*;
use crate::commands::ui::server::controlled_originals::ingress::{
    DocumentIngressLimits, DocumentSetupFault,
};

// Match the existing document/asset-end component INPUT, including the real
// fixed document decoder backing. The asset-only ENOUGH fixture is 2 MiB.
// This does not alter configuration defaults or the profile's allocations.
const FUSED_ENOUGH: Limits = Limits {
    retained: 8 * 1024 * 1024,
    work: 8 * 1024 * 1024,
    read: 1024 * 1024,
};

fn document_limits() -> DocumentIngressLimits {
    DocumentIngressLimits {
        observation_owners: 4,
        observation_events: 8,
        records: 4,
        journal_bytes: 8192,
        frame_bytes: 1024,
        socket_tasks: 6,
        request_tickets: 16,
        request_header_fields: 32,
        request_header_bytes: 1024,
    }
}

async fn observe_fused_host(
    host: &BoundControlledUiHost,
    end: Instant,
) -> Result<(u16, String, Response, u16, serde_json::Value, Response), Error> {
    let client = reqwest::Client::builder()
        .redirect(reqwest::redirect::Policy::none())
        .build()?;
    let launch = tokio::time::timeout_at(
        end.into(),
        client
            .get(host.launch_url())
            .header("Connection", "close")
            .send(),
    )
    .await??;
    let launch_status = launch.status().as_u16();
    let location = launch
        .headers()
        .get(reqwest::header::LOCATION)
        .ok_or_else(|| failure("actual fused launch location missing"))?
        .to_str()?
        .to_owned();
    let cookie = launch
        .headers()
        .get(reqwest::header::SET_COOKIE)
        .ok_or_else(|| failure("actual fused launch cookie missing"))?
        .to_str()?
        .split(';')
        .next()
        .ok_or_else(|| failure("actual fused launch cookie empty"))?
        .to_owned();
    drop(launch);
    let asset = fetch(
        &client,
        host,
        "/observed/product-observer.js",
        Some(&cookie),
        end,
    )
    .await?;
    let response = tokio::time::timeout_at(
        end.into(),
        client
            .post(format!("{}/_mck/document", host.base_url()))
            .header("Host", host.address().to_string())
            .header("Origin", host.base_url())
            .header("Cookie", &cookie)
            .header("Connection", "close")
            .body(Vec::<u8>::new())
            .send(),
    )
    .await??;
    let bootstrap_status = response.status().as_u16();
    let bytes = tokio::time::timeout_at(end.into(), response.bytes()).await??;
    let bootstrap = if bootstrap_status == 200 {
        serde_json::from_slice(&bytes)?
    } else {
        serde_json::Value::Null
    };
    let index = fetch(
        &client,
        host,
        "/observed/?mode=connected-originals",
        Some(&cookie),
        end,
    )
    .await?;
    Ok((
        launch_status,
        location,
        asset,
        bootstrap_status,
        bootstrap,
        index,
    ))
}

#[test]
fn browser_fused_host_01_same_image_cookie_source_and_original_end() {
    let fixture = Tiny::new(true);
    let files = fixture.files();
    let acquired = fixture.acquired(&files);
    let runtime = runtime();
    let ((actual, joined, same_backing, same_end, has_decoder), terminal) =
        scope(FUSED_ENOUGH, |clients, loans| {
            let stimulus = first_stimulus(clients, loans).unwrap();
            runtime.block_on(async {
                let original_end = Instant::now() + Duration::from_secs(30);
                let application =
                    RunObservedApplication::prepare(&acquired, loans, original_end).unwrap();
                let mut host = BoundControlledUiHost::bind_with_observed_document(
                    stimulus,
                    &application,
                    loans,
                    document_limits(),
                    original_end + Duration::from_secs(30),
                )
                .await
                .unwrap();
                let same_backing = host
                    .state
                    .assets
                    .as_ref()
                    .is_some_and(|assets| Arc::ptr_eq(&assets.image, &application.image));
                let same_end = host.state.end == original_end;
                let has_decoder = host.document_decoder.is_some();
                // Preserve the actual listener owner through every HTTP error;
                // assertions occur only after its real task registry joins.
                let actual = async {
                    host.start()
                        .map_err(|e| failure(format!("actual fused start: {e:?}")))?;
                    observe_fused_host(&host, original_end).await
                }
                .await;
                let joined = host.shutdown().await;
                (actual, joined, same_backing, same_end, has_decoder)
            })
        });
    assert_eq!(joined, ControlledHostShutdown::Joined);
    assert!(
        same_backing,
        "the host must borrow the once-prepared immutable image"
    );
    assert!(
        same_end,
        "a later caller end cannot extend the image's original end"
    );
    assert!(
        has_decoder,
        "the same host must own its funded document decoder"
    );
    let (launch, location, asset, bootstrap_status, bootstrap, index) = actual.unwrap();
    assert_eq!(launch, 303);
    assert_eq!(location, "/observed/?mode=connected-originals");
    assert_eq!(asset.status, 200);
    assert_eq!(asset.bytes, BODIES[2].1.len());
    assert_eq!(asset.sha256, digest(BODIES[2].1));
    assert_eq!(
        bootstrap_status, 200,
        "same-cookie ingress must be prepared on the asset host"
    );
    assert_eq!(bootstrap["records"], 4);
    assert_eq!(bootstrap["frameBytes"], 1024);
    assert_eq!(bootstrap["credential"].as_str().unwrap().len(), 43);
    assert_eq!(
        index.status, 503,
        "fusing owners does not enable an unprepared entry"
    );
    assert!(matches!(terminal, BrowserSourceTerminal::Incomplete { .. }));
}

#[test]
fn browser_fused_host_02_original_image_end_refuses_later_bind() {
    let fixture = Tiny::new(true);
    let files = fixture.files();
    let acquired = fixture.acquired(&files);
    let runtime = runtime();
    let ((refused, unexpected_join), _) = scope(FUSED_ENOUGH, |clients, loans| {
        let stimulus = first_stimulus(clients, loans).unwrap();
        runtime.block_on(async {
            let original_end = Instant::now() + Duration::from_millis(80);
            let application =
                RunObservedApplication::prepare(&acquired, loans, original_end).unwrap();
            tokio::time::sleep_until(original_end.into()).await;
            match BoundControlledUiHost::bind_with_observed_document(
                stimulus,
                &application,
                loans,
                document_limits(),
                original_end + Duration::from_secs(30),
            )
            .await
            {
                Err(DocumentSetupFault::Assets(ObservedAssetsFault::End)) => (true, None),
                Err(_) => (false, None),
                Ok(mut host) => (false, Some(host.shutdown().await)),
            }
        })
    });
    assert!(
        refused,
        "the fused constructor must preserve original image expiry"
    );
    assert!(unexpected_join.is_none());
}
