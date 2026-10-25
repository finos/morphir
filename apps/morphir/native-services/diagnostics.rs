//! Forward the canonical process channel's bounded diagnostics on stderr.
use async_trait::async_trait;
use morphir_extension_sdk::protocol::ExtensionResponse;
use morphir_host::{Channel, ChannelError, ChannelState, Outgoing};
use morphir_host_native::process::ProcessChannel;

pub struct Diagnostics {
    inner: ProcessChannel,
    emitted: usize,
}
impl Diagnostics {
    pub fn new(inner: ProcessChannel) -> Self {
        Self { inner, emitted: 0 }
    }
    fn emit(&mut self) {
        let text = self.inner.stderr_output();
        if text.len() > self.emitted {
            eprint!("{}", &text[self.emitted..]);
            self.emitted = text.len();
        }
    }
}
#[async_trait]
impl Channel for Diagnostics {
    async fn send(&mut self, message: Outgoing) -> Result<(), ChannelError> {
        let result = self.inner.send(message).await;
        if result.is_err() {
            self.emit();
        }
        result
    }
    async fn receive(&mut self) -> Result<ExtensionResponse, ChannelError> {
        let result = self.inner.receive().await;
        if result.is_err() {
            self.emit();
        }
        result
    }
    async fn close(&mut self) -> Result<ChannelState, ChannelError> {
        let result = self.inner.close().await;
        self.emit();
        result
    }
    async fn abort(&mut self) -> Result<ChannelState, ChannelError> {
        let result = self.inner.abort().await;
        self.emit();
        result
    }
}
