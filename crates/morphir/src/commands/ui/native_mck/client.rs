//! The ordinary authenticated loopback client, with caller-owned deadlines.
use std::{
    future::Future,
    sync::{
        Arc,
        atomic::{AtomicBool, Ordering},
    },
};

use futures_util::{SinkExt as _, StreamExt as _};
use morphir_mck::{
    transport::Limits,
    workbench::model_originals::native::{NativeAdapterError, data},
};
use serde_json::{Value, json};
use tokio::{task::JoinHandle, time::Instant};
use tokio_tungstenite::{
    MaybeTlsStream, WebSocketStream, connect_async_with_config,
    tungstenite::{Message, client::IntoClientRequest as _, protocol::WebSocketConfig},
};

use super::{
    super::{model_originals::PendingCaptureCleanup, server::BoundUiHost},
    completion::reconcile_completion,
};
type Socket = WebSocketStream<MaybeTlsStream<tokio::net::TcpStream>>;

pub(super) struct Deadline {
    pub limits: Limits,
    interrupted: Arc<AtomicBool>,
    end: Instant,
}
impl Deadline {
    pub fn new(limits: Limits, interrupted: Arc<AtomicBool>) -> Result<Self, NativeAdapterError> {
        Ok(Self {
            limits,
            interrupted,
            end: Instant::now()
                .checked_add(limits.session_timeout)
                .ok_or(NativeAdapterError::Startup)?,
        })
    }
    pub fn check(&self) -> Result<(), NativeAdapterError> {
        if self.interrupted.load(Ordering::SeqCst) {
            Err(NativeAdapterError::Cancelled)
        } else if Instant::now() >= self.end {
            Err(NativeAdapterError::Exchange)
        } else {
            Ok(())
        }
    }
    pub async fn exchange<T>(
        &self,
        future: impl Future<Output = Result<T, NativeAdapterError>>,
    ) -> Result<T, NativeAdapterError> {
        self.check()?;
        let end = self.end.min(
            Instant::now()
                .checked_add(self.limits.request_timeout)
                .unwrap_or(self.end),
        );
        tokio::select! {
            result = future => result,
            () = tokio::time::sleep_until(end) => Err(NativeAdapterError::Exchange),
            () = async {
                while !self.interrupted.load(Ordering::SeqCst) {
                    tokio::time::sleep(std::time::Duration::from_millis(10)).await;
                }
            } => Err(NativeAdapterError::Cancelled),
        }
    }
}

pub(super) struct RunningHost {
    server: Option<JoinHandle<Result<(), crate::error::CliError>>>,
    socket: Option<Socket>,
    capture_cleanup: CaptureCleanup,
    base: String,
    launch: String,
}
enum CaptureCleanup {
    Pending(PendingCaptureCleanup),
    Joined,
}
impl RunningHost {
    pub fn start(mut host: BoundUiHost) -> Result<Self, NativeAdapterError> {
        // Synchronous conversion moves the SAME registry into this owner
        // before serve or any await. No boxed drain future or reaper owns it.
        let capture_cleanup = host
            .take_capture_cleanup()
            .map_err(|_| NativeAdapterError::Startup)?
            .into_pending();
        let base = host.base_url();
        let launch = host.launch_url();
        Ok(Self {
            server: Some(tokio::spawn(host.serve())),
            socket: None,
            capture_cleanup: CaptureCleanup::Pending(capture_cleanup),
            base,
            launch,
        })
    }
    pub async fn connect(&mut self, deadline: &Deadline) -> Result<(), NativeAdapterError> {
        let client = reqwest::Client::builder()
            .redirect(reqwest::redirect::Policy::none())
            .build()
            .map_err(|_| NativeAdapterError::Authentication)?;
        let response = deadline
            .exchange(async {
                client
                    .get(&self.launch)
                    .send()
                    .await
                    .map_err(|_| NativeAdapterError::Authentication)
            })
            .await?;
        if response.status() != reqwest::StatusCode::SEE_OTHER {
            return Err(NativeAdapterError::Authentication);
        }
        let cookie = response
            .headers()
            .get("set-cookie")
            .and_then(|v| v.to_str().ok())
            .and_then(|v| v.split(';').next())
            .ok_or(NativeAdapterError::Authentication)?;
        let mut request = format!("{}/rpc", self.base.replace("http://", "ws://"))
            .into_client_request()
            .map_err(|_| NativeAdapterError::Authentication)?;
        request.headers_mut().insert(
            "origin",
            self.base
                .parse()
                .map_err(|_| NativeAdapterError::Authentication)?,
        );
        request.headers_mut().insert(
            "cookie",
            cookie
                .parse()
                .map_err(|_| NativeAdapterError::Authentication)?,
        );
        let configuration = WebSocketConfig::default()
            .max_message_size(Some(deadline.limits.max_frame))
            .max_frame_size(Some(deadline.limits.max_frame));
        let (socket, _) = deadline
            .exchange(async {
                connect_async_with_config(request, Some(configuration), false)
                    .await
                    .map_err(|_| NativeAdapterError::Authentication)
            })
            .await?;
        self.socket = Some(socket);
        Ok(())
    }
    pub async fn request(
        &mut self,
        deadline: &Deadline,
        id: u64,
        method: &str,
        params: Value,
    ) -> Result<(Value, data::MeasuredTranscriptExchangesItem), NativeAdapterError> {
        let request =
            json!({"jsonrpc":"2.0", "id":id, "method":method, "params":params}).to_string();
        if request.len() > deadline.limits.max_frame {
            return Err(NativeAdapterError::Exchange);
        }
        let socket = self.socket.as_mut().ok_or(NativeAdapterError::Exchange)?;
        let reply = deadline
            .exchange(async {
                socket
                    .send(Message::Text(request.clone().into()))
                    .await
                    .map_err(|_| NativeAdapterError::Exchange)?;
                loop {
                    match socket
                        .next()
                        .await
                        .ok_or(NativeAdapterError::Exchange)?
                        .map_err(|_| NativeAdapterError::Exchange)?
                    {
                        Message::Text(text) => return Ok(text.to_string()),
                        Message::Ping(_) | Message::Pong(_) => {}
                        _ => return Err(NativeAdapterError::Exchange),
                    }
                }
            })
            .await?;
        let value: Value =
            serde_json::from_str(&reply).map_err(|_| NativeAdapterError::Exchange)?;
        if value.get("id").and_then(Value::as_u64) != Some(id) || value.get("error").is_some() {
            tracing::warn!(method,id,actual_id=?value.get("id"),error=?value.get("error"),"Native host exchange refused");
            return Err(NativeAdapterError::Exchange);
        }
        let frames = data::MeasuredTranscriptExchangesItem {
            request: data::Frame::Literal {
                text: data::Text::new(&request).map_err(|_| NativeAdapterError::Exchange)?,
            },
            reply: data::Frame::Literal {
                text: data::Text::new(&reply).map_err(|_| NativeAdapterError::Exchange)?,
            },
        };
        Ok((value, frames))
    }
    pub async fn disconnect(&mut self, end: Instant) -> Result<(), NativeAdapterError> {
        let result = match self.socket.as_mut() {
            Some(socket) => tokio::time::timeout_at(end, socket.close(None)).await,
            None => return Ok(()),
        };
        // A cancelled or timed-out close keeps the actual socket for retry.
        // A completed close/error retires this owned transport, never a worker.
        match result {
            Ok(Ok(())) => {
                self.socket = None;
                Ok(())
            }
            Ok(Err(_)) => {
                self.socket = None;
                Err(NativeAdapterError::Cleanup)
            }
            Err(_) => Err(NativeAdapterError::Cleanup),
        }
    }
    pub async fn stop(&mut self, end: Instant) -> Result<(), NativeAdapterError> {
        let close = self.disconnect(end).await;
        let listener = if let Some(server) = self.server.as_mut() {
            server.abort();
            match tokio::time::timeout_at(end, server).await {
                Ok(Err(error)) if error.is_cancelled() => {
                    self.server = None;
                    Ok(())
                }
                Ok(Ok(Ok(()))) => {
                    self.server = None;
                    Ok(())
                }
                Ok(_) => {
                    self.server = None;
                    Err(NativeAdapterError::Cleanup)
                }
                // The same real JoinHandle remains in its field on deadline
                // or when this borrowed await is cancelled by the caller.
                Err(_) => Err(NativeAdapterError::Cleanup),
            }
        } else {
            Ok(())
        };
        let captures = match &mut self.capture_cleanup {
            CaptureCleanup::Pending(owner) => owner
                .drain_retained(end)
                .await
                .map_err(|_| NativeAdapterError::Cleanup),
            CaptureCleanup::Joined => Ok(()),
        };
        if captures.is_ok() {
            self.capture_cleanup = CaptureCleanup::Joined;
        }
        // Listener completion is not a join of framework-upgraded tasks.
        // The caller still requires real source sealing and worker cleanup.
        reconcile_completion(reconcile_completion(close, listener), captures)
    }
}
impl Drop for RunningHost {
    fn drop(&mut self) {
        if let Some(server) = &self.server {
            server.abort();
        }
    }
}

#[cfg(test)]
mod cleanup_tests;
