//! Closed launch spelling at the physical controller boundary. This nominal
//! value is DATA only, not an engine-issued run or authenticated host grant.
use super::ControllerFault;

// Deliberately no Debug: the one-use credential is not process diagnostics.
pub(in super::super) struct ObservedLaunch(String);
impl ObservedLaunch {
    pub(in super::super) fn parse(input: String) -> Result<Self, ControllerFault> {
        let rest = input
            .strip_prefix("http://127.0.0.1:")
            .ok_or(ControllerFault::Shape)?;
        let (port, token) = rest
            .split_once("/launch?token=")
            .ok_or(ControllerFault::Shape)?;
        if port.is_empty()
            || port.len() > 5
            || port.starts_with('0')
            || !port.bytes().all(|byte| byte.is_ascii_digit())
            || port.parse::<u16>().ok().is_none_or(|port| port == 0)
            || token.len() != 43
            || !token
                .bytes()
                .all(|byte| byte.is_ascii_alphanumeric() || matches!(byte, b'-' | b'_'))
            || !matches!(
                token.as_bytes()[42],
                b'A' | b'E'
                    | b'I'
                    | b'M'
                    | b'Q'
                    | b'U'
                    | b'Y'
                    | b'c'
                    | b'g'
                    | b'k'
                    | b'o'
                    | b's'
                    | b'w'
                    | b'0'
                    | b'4'
                    | b'8'
            )
        {
            return Err(ControllerFault::Shape);
        }
        Ok(Self(input))
    }
    pub(in super::super) fn as_str(&self) -> &str {
        &self.0
    }
}
