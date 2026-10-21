//! Non-default development controls on genuine owned endpoints and tickets.
use super::*;
#[derive(Debug, Clone, Copy)]
pub enum ConsumerTestFact {
    Release,
    Commit,
}
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct ConsumerTestUsage {
    pub receiving: InstalledObservationUsage,
    pub decoder: [usize; 4],
}
impl InstalledClientRun<'_> {
    pub fn test_consumer_usage(&self) -> ConsumerTestUsage {
        let usage = self.decode.usage();
        ConsumerTestUsage {
            receiving: self.installed_observation_usage(),
            decoder: [
                usage.literal.decode_bytes,
                usage.literal.values,
                usage.byte_visits,
                usage.slots,
            ],
        }
    }
    /// Validate the SAME live ticket/cache association before closing only its
    /// actual parent's write half. The next production write measures its error.
    pub fn test_shutdown_consumer_ack(
        &mut self,
        ports: &mut InstalledConsumerPorts,
        ticket: &ConsumerPendingAck,
        kind: ConsumerTestFact,
    ) -> Result<bool, InstalledAdapterError> {
        #[cfg(target_os = "macos")]
        {
            self.check_consumer_ports(ports)
                .map_err(|_| InstalledAdapterError::ObservationIncomplete)?;
            if !ticket.control.ptr_eq(&Arc::downgrade(&ports.control)) || ticket.cursor != 0 {
                return Ok(false);
            }
            let Some(row) =
                self.collected.consumer_cache[ticket.role.index()].get(ticket.cache_index)
            else {
                return Ok(false);
            };
            if row.sequence() != ticket.sequence {
                return Ok(false);
            }
            let matches = matches!(
                (kind, &row.frame),
                (
                    ConsumerTestFact::Release,
                    wire::Frame::Fact {
                        fact: wire::Fact::Release { .. },
                        ..
                    }
                ) | (
                    ConsumerTestFact::Commit,
                    wire::Frame::Fact {
                        fact: wire::Fact::Commit { .. },
                        ..
                    }
                )
            );
            if !matches {
                return Ok(false);
            }
            let parent = &ports
                .control
                .parents
                .get()
                .ok_or(InstalledAdapterError::ObservationIncomplete)?[ticket.role.index()];
            parent
                .shutdown(Shutdown::Write)
                .map_err(|_| InstalledAdapterError::ObservationIncomplete)?;
            Ok(true)
        }
        #[cfg(not(target_os = "macos"))]
        {
            let _ = (ports, ticket, kind);
            Err(InstalledAdapterError::ObservationIncomplete)
        }
    }
}
