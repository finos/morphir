//! One-time launch authentication for the loopback UI host.

use std::sync::Mutex;

use base64::{Engine as _, engine::general_purpose::URL_SAFE_NO_PAD};
use subtle::ConstantTimeEq as _;

use crate::error::CliError;

const SECRET_BYTES: usize = 32;
pub const SESSION_COOKIE_NAME: &str = "morphir_session";

pub struct SessionAuth {
    launch_secret: Mutex<Option<[u8; SECRET_BYTES]>>,
    session_secret: [u8; SECRET_BYTES],
}

impl SessionAuth {
    pub fn generate() -> Result<(Self, String), CliError> {
        let mut launch_secret = [0_u8; SECRET_BYTES];
        let mut session_secret = [0_u8; SECRET_BYTES];
        getrandom::fill(&mut launch_secret).map_err(|error| CliError::Validation {
            message: format!("Unable to generate launch authentication: {error}"),
        })?;
        getrandom::fill(&mut session_secret).map_err(|error| CliError::Validation {
            message: format!("Unable to generate session authentication: {error}"),
        })?;
        let launch_token = URL_SAFE_NO_PAD.encode(launch_secret);
        Ok((
            Self {
                launch_secret: Mutex::new(Some(launch_secret)),
                session_secret,
            },
            launch_token,
        ))
    }

    #[cfg(test)]
    fn from_secrets(
        launch_secret: [u8; SECRET_BYTES],
        session_secret: [u8; SECRET_BYTES],
    ) -> (Self, String) {
        let token = URL_SAFE_NO_PAD.encode(launch_secret);
        (
            Self {
                launch_secret: Mutex::new(Some(launch_secret)),
                session_secret,
            },
            token,
        )
    }

    pub fn exchange_launch_token(&self, candidate: &str) -> bool {
        let Ok(candidate) = decode_secret(candidate) else {
            return false;
        };
        let mut launch_secret = self
            .launch_secret
            .lock()
            .expect("launch authentication mutex is not poisoned");
        let matches = launch_secret
            .as_ref()
            .is_some_and(|expected| expected.ct_eq(&candidate).into());
        if matches {
            launch_secret.take();
        }
        matches
    }

    pub fn session_cookie(&self) -> String {
        format!(
            "{SESSION_COOKIE_NAME}={}; HttpOnly; SameSite=Strict; Path=/",
            URL_SAFE_NO_PAD.encode(self.session_secret)
        )
    }

    pub fn authenticate_cookie_header(&self, header: &str) -> bool {
        header.split(';').any(|part| {
            let Some((name, value)) = part.trim().split_once('=') else {
                return false;
            };
            if name != SESSION_COOKIE_NAME {
                return false;
            }
            decode_secret(value).is_ok_and(|candidate| self.session_secret.ct_eq(&candidate).into())
        })
    }
}

fn decode_secret(encoded: &str) -> Result<[u8; SECRET_BYTES], ()> {
    let bytes = URL_SAFE_NO_PAD.decode(encoded).map_err(|_| ())?;
    bytes.try_into().map_err(|_| ())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn launch_token_is_single_use_and_wrong_values_do_not_consume_it() {
        let (auth, token) = SessionAuth::from_secrets([7; SECRET_BYTES], [9; SECRET_BYTES]);

        assert!(!auth.exchange_launch_token("wrong"));
        assert!(auth.exchange_launch_token(&token));
        assert!(!auth.exchange_launch_token(&token));
    }

    #[test]
    fn session_cookie_is_strict_http_only_and_path_scoped() {
        let (auth, _) = SessionAuth::from_secrets([7; SECRET_BYTES], [9; SECRET_BYTES]);
        let cookie = auth.session_cookie();

        assert!(cookie.contains("HttpOnly"));
        assert!(cookie.contains("SameSite=Strict"));
        assert!(cookie.contains("Path=/"));
        let pair = cookie.split(';').next().unwrap();
        assert!(auth.authenticate_cookie_header(pair));
        assert!(auth.authenticate_cookie_header(&format!("other=value; {pair}")));
        assert!(!auth.authenticate_cookie_header("morphir_session=wrong"));
    }
}
