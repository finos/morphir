//! Cryptographic structures and functions.

use {
    data_encoding::HEXLOWER,
    futures_io::AsyncRead,
    futures_util::AsyncReadExt as _,
    ring::{
        digest::{self, SHA256, SHA512},
        rand::SystemRandom,
        signature::{Ed25519KeyPair, KeyPair, ED25519},
    },
    serde::{
        de::Error as DeserializeError, ser::Error as SerializeError, Deserialize, Deserializer,
        Serialize, Serializer,
    },
    std::{
        cmp::Ordering,
        collections::HashMap,
        fmt::{self, Debug, Display},
        hash,
        str::FromStr,
    },
    untrusted::Input,
};

use crate::error::{Error, Result};
use crate::metadata::MetadataPath;
use crate::pouf::pouf1::shims;

const HASH_ALG_PREFS: &[HashAlgorithm] = &[HashAlgorithm::Sha512, HashAlgorithm::Sha256];

/// 1.3.101.112 curveEd25519(EdDSA 25519 signature algorithm)
const ED25519_SPKI_HEADER: &[u8] = &[
    0x30, 0x2c, 0x30, 0x07, 0x06, 0x03, 0x2b, 0x65, 0x70, 0x05, 0x00, 0x03, 0x21, 0x00,
];

/// The length of an ed25519 private key in bytes
const ED25519_PRIVATE_KEY_LENGTH: usize = 32;

/// The length of an ed25519 public key in bytes
const ED25519_PUBLIC_KEY_LENGTH: usize = 32;

/// The length of an ed25519 keypair in bytes
const ED25519_KEYPAIR_LENGTH: usize = ED25519_PRIVATE_KEY_LENGTH + ED25519_PUBLIC_KEY_LENGTH;

fn python_tuf_compatibility_keyid_hash_algorithms() -> Option<Vec<String>> {
    Some(vec!["sha256".to_string(), "sha512".to_string()])
}

/// Given a map of hash algorithms and their values and retains the supported
/// hashes. Returns an `Err` if there is no match.
///
/// ```
/// use std::collections::HashMap;
/// use tuf::crypto::{retain_supported_hashes, HashValue, HashAlgorithm};
///
/// let mut map = HashMap::new();
/// assert!(retain_supported_hashes(&map).is_empty());
///
/// let sha512_value = HashValue::new(vec![0x00, 0x01]);
/// let _ = map.insert(HashAlgorithm::Sha512, sha512_value.clone());
/// assert_eq!(
///     retain_supported_hashes(&map),
///     vec![
///         (&HashAlgorithm::Sha512, sha512_value.clone()),
///     ],
/// );
///
/// let sha256_value = HashValue::new(vec![0x02, 0x03]);
/// let _ = map.insert(HashAlgorithm::Sha256, sha256_value.clone());
/// assert_eq!(
///     retain_supported_hashes(&map),
///     vec![
///         (&HashAlgorithm::Sha512, sha512_value.clone()),
///         (&HashAlgorithm::Sha256, sha256_value.clone()),
///     ],
/// );
///
/// let md5_value = HashValue::new(vec![0x04, 0x05]);
/// let _ = map.insert(HashAlgorithm::Unknown("md5".into()), md5_value);
/// assert_eq!(
///     retain_supported_hashes(&map),
///     vec![
///         (&HashAlgorithm::Sha512, sha512_value),
///         (&HashAlgorithm::Sha256, sha256_value),
///     ],
/// );
/// ```
pub fn retain_supported_hashes(
    hashes: &HashMap<HashAlgorithm, HashValue>,
) -> Vec<(&'static HashAlgorithm, HashValue)> {
    let mut data = vec![];
    for alg in HASH_ALG_PREFS {
        if let Some(value) = hashes.get(alg) {
            data.push((alg, value.clone()));
        }
    }

    data
}

#[cfg(test)]
pub(crate) fn calculate_hash(data: &[u8], hash_alg: &HashAlgorithm) -> HashValue {
    let mut context = hash_alg.digest_context().unwrap();
    context.update(data);
    HashValue::new(context.finish().as_ref().to_vec())
}

/// Calculate the size and hash digest from a given `AsyncRead`.
pub fn calculate_hashes_from_slice(
    buf: &[u8],
    hash_algs: &[HashAlgorithm],
) -> Result<HashMap<HashAlgorithm, HashValue>> {
    if hash_algs.is_empty() {
        return Err(Error::IllegalArgument(
            "Cannot provide empty set of hash algorithms".into(),
        ));
    }

    let mut hashes = HashMap::new();
    for alg in hash_algs {
        let mut context = alg.digest_context()?;
        context.update(buf);

        hashes.insert(
            alg.clone(),
            HashValue::new(context.finish().as_ref().to_vec()),
        );
    }

    Ok(hashes)
}

/// Calculate the size and hash digest from a given `AsyncRead`.
pub async fn calculate_hashes_from_reader<R>(
    mut read: R,
    hash_algs: &[HashAlgorithm],
) -> Result<(u64, HashMap<HashAlgorithm, HashValue>)>
where
    R: AsyncRead + Unpin,
{
    if hash_algs.is_empty() {
        return Err(Error::IllegalArgument(
            "Cannot provide empty set of hash algorithms".into(),
        ));
    }

    let mut size = 0;
    let mut hashes = HashMap::new();
    for alg in hash_algs {
        let _ = hashes.insert(alg, alg.digest_context()?);
    }

    let mut buf = vec![0; 1024];
    loop {
        match read.read(&mut buf).await {
            Ok(read_bytes) => {
                if read_bytes == 0 {
                    break;
                }

                size += read_bytes as u64;

                for context in hashes.values_mut() {
                    context.update(&buf[0..read_bytes]);
                }
            }
            e @ Err(_) => e.map(|_| ())?,
        }
    }

    let hashes = hashes
        .drain()
        .map(|(k, v)| (k.clone(), HashValue::new(v.finish().as_ref().to_vec())))
        .collect();
    Ok((size, hashes))
}

fn shim_public_key(
    key_type: &KeyType,
    signature_scheme: &SignatureScheme,
    keyid_hash_algorithms: &Option<Vec<String>>,
    public_key: &[u8],
) -> Result<shims::PublicKey> {
    let key = match (key_type, signature_scheme) {
        (KeyType::Ed25519, SignatureScheme::Ed25519) => HEXLOWER.encode(public_key),
        (_, _) => {
            // We don't understand this key type and/or signature scheme, so we left it as a UTF-8 string.
            std::str::from_utf8(public_key)
                .map_err(|err| {
                    Error::Encoding(format!(
                        "error converting public key value {:?} with key \
                        type {:?} and signature scheme {:?} to a string: {:?}",
                        public_key, key_type, signature_scheme, err
                    ))
                })?
                .to_string()
        }
    };

    Ok(shims::PublicKey::new(
        key_type.clone(),
        signature_scheme.clone(),
        keyid_hash_algorithms.clone(),
        key,
    ))
}

fn calculate_key_id(
    key_type: &KeyType,
    signature_scheme: &SignatureScheme,
    keyid_hash_algorithms: &Option<Vec<String>>,
    public_key: &[u8],
) -> Result<KeyId> {
    use crate::pouf::{Pouf, Pouf1};

    let public_key = shim_public_key(
        key_type,
        signature_scheme,
        keyid_hash_algorithms,
        public_key,
    )?;
    let public_key = Pouf1::canonicalize(&Pouf1::serialize(&public_key)?)?;
    let mut context = digest::Context::new(&SHA256);
    context.update(&public_key);

    let key_id = HEXLOWER.encode(context.finish().as_ref());

    Ok(KeyId(key_id))
}

/// Wrapper type for public key's ID.
///
/// # Calculating
///
/// A `KeyId` is calculated as the hex digest of the SHA-256 hash of the
/// canonical form of the public key, or `hexdigest(sha256(cjson(public_key)))`.
#[derive(Clone, Debug, PartialEq, Eq, Hash, PartialOrd, Ord)]
pub struct KeyId(String);

impl FromStr for KeyId {
    type Err = Error;

    /// Parse a key ID from a string.
    fn from_str(string: &str) -> Result<Self> {
        if string.len() != 64 {
            return Err(Error::IllegalArgument(
                "key ID must be 64 characters long".into(),
            ));
        }
        Ok(KeyId(string.to_owned()))
    }
}

impl fmt::Display for KeyId {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(&self.0)
    }
}

impl Serialize for KeyId {
    fn serialize<S>(&self, ser: S) -> ::std::result::Result<S::Ok, S::Error>
    where
        S: Serializer,
    {
        self.0.serialize(ser)
    }
}

impl<'de> Deserialize<'de> for KeyId {
    fn deserialize<D: Deserializer<'de>>(de: D) -> ::std::result::Result<Self, D::Error> {
        let string: String = Deserialize::deserialize(de)?;
        KeyId::from_str(&string).map_err(|e| DeserializeError::custom(format!("{:?}", e)))
    }
}

/// Cryptographic signature schemes.
#[non_exhaustive]
#[derive(Debug, Clone, PartialEq, Eq, Hash)]
pub enum SignatureScheme {
    /// [Ed25519](https://ed25519.cr.yp.to/)
    Ed25519,

    /// Placeholder for an unknown scheme.
    Unknown(String),
}

impl SignatureScheme {
    /// Construct a signature scheme from a `&str`.
    pub fn new(name: &str) -> Self {
        match name {
            "ed25519" => SignatureScheme::Ed25519,
            scheme => SignatureScheme::Unknown(scheme.to_string()),
        }
    }

    /// Return the signature scheme as a `&str`.
    pub fn as_str(&self) -> &str {
        match *self {
            SignatureScheme::Ed25519 => "ed25519",
            SignatureScheme::Unknown(ref s) => s,
        }
    }
}

impl Display for SignatureScheme {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(self.as_str())
    }
}

impl Serialize for SignatureScheme {
    fn serialize<S>(&self, ser: S) -> ::std::result::Result<S::Ok, S::Error>
    where
        S: Serializer,
    {
        ser.serialize_str(self.as_str())
    }
}

impl<'de> Deserialize<'de> for SignatureScheme {
    fn deserialize<D: Deserializer<'de>>(de: D) -> ::std::result::Result<Self, D::Error> {
        let string: String = Deserialize::deserialize(de)?;
        Ok(Self::new(&string))
    }
}

/// Wrapper type for the value of a cryptographic signature.
#[derive(Clone, PartialEq, Eq, PartialOrd, Ord, Serialize, Deserialize)]
pub struct SignatureValue(#[serde(with = "crate::format_hex")] Vec<u8>);

impl SignatureValue {
    /// Create a new `SignatureValue` from the given bytes.
    ///
    /// Note: It is unlikely that you ever want to do this manually.
    pub fn new(bytes: Vec<u8>) -> Self {
        SignatureValue(bytes)
    }

    /// Return the signature as bytes.
    pub fn as_bytes(&self) -> &[u8] {
        &self.0
    }
}

impl Debug for SignatureValue {
    fn fmt(&self, f: &mut fmt::Formatter) -> fmt::Result {
        f.debug_tuple("SignatureValue")
            .field(&HEXLOWER.encode(&self.0))
            .finish()
    }
}

/// Types of public keys.
#[non_exhaustive]
#[derive(Clone, PartialEq, Debug, Eq, Hash)]
pub enum KeyType {
    /// [Ed25519](https://ed25519.cr.yp.to/)
    Ed25519,

    /// Placeholder for an unknown key type.
    Unknown(String),
}

impl KeyType {
    /// Construct a key type from a `&str`.
    pub fn new(name: &str) -> Self {
        match name {
            "ed25519" => KeyType::Ed25519,
            keytype => KeyType::Unknown(keytype.to_string()),
        }
    }

    /// Return the key type as a `&str`.
    pub fn as_str(&self) -> &str {
        match *self {
            KeyType::Ed25519 => "ed25519",
            KeyType::Unknown(ref s) => s,
        }
    }
}

impl Display for KeyType {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(self.as_str())
    }
}

impl Serialize for KeyType {
    fn serialize<S>(&self, ser: S) -> ::std::result::Result<S::Ok, S::Error>
    where
        S: Serializer,
    {
        ser.serialize_str(self.as_str())
    }
}

impl<'de> Deserialize<'de> for KeyType {
    fn deserialize<D: Deserializer<'de>>(de: D) -> ::std::result::Result<Self, D::Error> {
        let string: String = Deserialize::deserialize(de)?;
        Ok(Self::new(&string))
    }
}

/// A structure containing information about a private key.
pub trait PrivateKey {
    /// Sign a message.
    fn sign(&self, msg: &[u8]) -> Result<Signature>;

    /// Return the public component of the key.
    fn public(&self) -> &PublicKey;
}

/// A structure containing information about an Ed25519 private key.
pub struct Ed25519PrivateKey {
    private: Ed25519KeyPair,
    public: PublicKey,
}

impl Ed25519PrivateKey {
    /// Generate Ed25519 key bytes in pkcs8 format.
    pub fn pkcs8() -> Result<Vec<u8>> {
        Ed25519KeyPair::generate_pkcs8(&SystemRandom::new())
            .map(|bytes| bytes.as_ref().to_vec())
            .map_err(|_| Error::Opaque("Failed to generate Ed25519 key".into()))
    }

    /// Create a new `PrivateKey` from an ed25519 keypair. The keypair is a 64 byte slice, where the
    /// first 32 bytes are the ed25519 seed, and the second 32 bytes are the public key.
    pub fn from_ed25519(key: &[u8]) -> Result<Self> {
        Self::from_ed25519_with_keyid_hash_algorithms(key, None)
    }

    /// Create a new `PrivateKey` from an ed25519 keypair with a custom `keyid_hash_algorithms`. The
    /// keypair is a 64 byte slice, where the first 32 bytes are the ed25519 seed, and the second 32
    /// bytes are the public key.
    pub fn from_ed25519_with_keyid_hash_algorithms(
        key: &[u8],
        keyid_hash_algorithms: Option<Vec<String>>,
    ) -> Result<Self> {
        if key.len() != ED25519_KEYPAIR_LENGTH {
            return Err(Error::Encoding(
                "ed25519 private keys must be 64 bytes long".into(),
            ));
        }

        let private_key_bytes = &key[..ED25519_PRIVATE_KEY_LENGTH];
        let public_key_bytes = &key[ED25519_PUBLIC_KEY_LENGTH..];

        let private = Ed25519KeyPair::from_seed_and_public_key(private_key_bytes, public_key_bytes)
            .map_err(|err| Error::Encoding(err.to_string()))?;
        Self::from_keypair_with_keyid_hash_algorithms(private, keyid_hash_algorithms)
    }

    /// Create a private key from PKCS#8v2 DER bytes.
    ///
    /// # Generating Keys
    ///
    /// ```bash
    /// $ touch ed25519-private-key.pk8
    /// $ chmod 0600 ed25519-private-key.pk8
    /// ```
    ///
    /// ```no_run
    /// # use ring::rand::SystemRandom;
    /// # use ring::signature::Ed25519KeyPair;
    /// # use std::fs::File;
    /// # use std::io::Write;
    /// #
    /// let mut file = File::open("ed25519-private-key.pk8").unwrap();
    /// let key = Ed25519KeyPair::generate_pkcs8(&SystemRandom::new()).unwrap();
    /// file.write_all(key.as_ref()).unwrap()
    /// ```
    pub fn from_pkcs8(der_key: &[u8]) -> Result<Self> {
        Self::from_pkcs8_with_keyid_hash_algorithms(
            der_key,
            python_tuf_compatibility_keyid_hash_algorithms(),
        )
    }

    fn from_pkcs8_with_keyid_hash_algorithms(
        der_key: &[u8],
        keyid_hash_algorithms: Option<Vec<String>>,
    ) -> Result<Self> {
        Self::from_keypair_with_keyid_hash_algorithms(
            Ed25519KeyPair::from_pkcs8(der_key)
                .map_err(|_| Error::Encoding("Could not parse key as PKCS#8v2".into()))?,
            keyid_hash_algorithms,
        )
    }

    fn from_keypair_with_keyid_hash_algorithms(
        private: Ed25519KeyPair,
        keyid_hash_algorithms: Option<Vec<String>>,
    ) -> Result<Self> {
        let public = PublicKey::new(
            KeyType::Ed25519,
            SignatureScheme::Ed25519,
            keyid_hash_algorithms,
            private.public_key().as_ref().to_vec(),
        )?;

        Ok(Ed25519PrivateKey { private, public })
    }
}

impl PrivateKey for Ed25519PrivateKey {
    fn sign(&self, msg: &[u8]) -> Result<Signature> {
        debug_assert!(self.public.scheme == SignatureScheme::Ed25519);

        let value = SignatureValue(self.private.sign(msg).as_ref().into());
        Ok(Signature {
            key_id: self.public.key_id().clone(),
            value,
        })
    }

    fn public(&self) -> &PublicKey {
        &self.public
    }
}

/// A structure containing information about a public key.
#[derive(Clone, Debug)]
pub struct PublicKey {
    typ: KeyType,
    key_id: KeyId,
    scheme: SignatureScheme,
    keyid_hash_algorithms: Option<Vec<String>>,
    value: PublicKeyValue,
}

impl PublicKey {
    fn new(
        typ: KeyType,
        scheme: SignatureScheme,
        keyid_hash_algorithms: Option<Vec<String>>,
        value: Vec<u8>,
    ) -> Result<Self> {
        let key_id = calculate_key_id(&typ, &scheme, &keyid_hash_algorithms, &value)?;
        let value = PublicKeyValue(value);
        Ok(PublicKey {
            typ,
            key_id,
            scheme,
            keyid_hash_algorithms,
            value,
        })
    }

    /// Parse DER bytes as an SPKI key.
    ///
    /// See the documentation on `KeyValue` for more information on SPKI.
    pub fn from_spki(der_bytes: &[u8], scheme: SignatureScheme) -> Result<Self> {
        Self::from_spki_with_keyid_hash_algorithms(
            der_bytes,
            scheme,
            python_tuf_compatibility_keyid_hash_algorithms(),
        )
    }

    /// Parse DER bytes as an SPKI key and the `keyid_hash_algorithms`.
    ///
    /// See the documentation on `KeyValue` for more information on SPKI.
    fn from_spki_with_keyid_hash_algorithms(
        der_bytes: &[u8],
        scheme: SignatureScheme,
        keyid_hash_algorithms: Option<Vec<String>>,
    ) -> Result<Self> {
        fn der_error(s: &str) -> Error {
            Error::Encoding(s.into())
        }

        let (typ, expected_header) = match scheme {
            SignatureScheme::Ed25519 => (KeyType::Ed25519, ED25519_SPKI_HEADER),
            SignatureScheme::Unknown(s) => {
                return Err(Error::UnknownSignatureScheme(s));
            }
        };

        let input = Input::from(der_bytes);
        let value = input.read_all(der_error("DER: unexpected trailing input"), |input| {
            let actual_header = input
                .read_bytes(expected_header.len())
                .map_err(|_: untrusted::EndOfInput| der_error("DER: Invalid SPKI header"))?;
            if actual_header.as_slice_less_safe() != expected_header {
                return Err(Error::Encoding("DER: Unsupported SPKI header value".into()));
            }
            let value = input
                .read_bytes(ED25519_PUBLIC_KEY_LENGTH)
                .map_err(|_: untrusted::EndOfInput| der_error("DER: Invalid SPKI value"))?;
            Ok(value.as_slice_less_safe().to_vec())
        })?;

        Self::new(typ, scheme, keyid_hash_algorithms, value)
    }

    /// Parse ED25519 bytes as a public key.
    pub fn from_ed25519<T: Into<Vec<u8>>>(bytes: T) -> Result<Self> {
        Self::from_ed25519_with_keyid_hash_algorithms(bytes, None)
    }

    /// Parse ED25519 bytes as a public key with a custom `keyid_hash_algorithms`.
    pub fn from_ed25519_with_keyid_hash_algorithms<T: Into<Vec<u8>>>(
        bytes: T,
        keyid_hash_algorithms: Option<Vec<String>>,
    ) -> Result<Self> {
        let bytes = bytes.into();
        if bytes.len() != 32 {
            return Err(Error::IllegalArgument(
                "ed25519 keys must be 32 bytes long".into(),
            ));
        }

        Self::new(
            KeyType::Ed25519,
            SignatureScheme::Ed25519,
            keyid_hash_algorithms,
            bytes,
        )
    }

    /// Write the public key as SPKI DER bytes.
    ///
    /// See the documentation on `KeyValue` for more information on SPKI.
    pub fn as_spki(&self) -> Result<Vec<u8>> {
        write_spki(&self.value.0, &self.typ)
    }

    /// An immutable reference to the key's type.
    pub fn typ(&self) -> &KeyType {
        &self.typ
    }

    /// An immutable referece to the key's authorized signing scheme.
    pub fn scheme(&self) -> &SignatureScheme {
        &self.scheme
    }

    /// An immutable reference to the key's ID.
    pub fn key_id(&self) -> &KeyId {
        &self.key_id
    }

    /// Return the public key as bytes.
    pub fn as_bytes(&self) -> &[u8] {
        &self.value.0
    }

    /// Use this key to verify a message with a signature.
    pub fn verify(&self, role: &MetadataPath, msg: &[u8], sig: &Signature) -> Result<()> {
        let alg: &dyn ring::signature::VerificationAlgorithm = match self.scheme {
            SignatureScheme::Ed25519 => &ED25519,
            SignatureScheme::Unknown(ref s) => {
                return Err(Error::UnknownSignatureScheme(s.to_string()));
            }
        };

        let key = ring::signature::UnparsedPublicKey::new(alg, &self.value.0);
        key.verify(msg, &sig.value.0)
            .map_err(|_| Error::BadSignature(role.clone()))
    }
}

impl PartialEq for PublicKey {
    fn eq(&self, other: &Self) -> bool {
        // key_id is derived from these fields, so we ignore it.
        self.typ == other.typ
            && self.scheme == other.scheme
            && self.keyid_hash_algorithms == other.keyid_hash_algorithms
            && self.value == other.value
    }
}

impl Eq for PublicKey {}

impl Ord for PublicKey {
    fn cmp(&self, other: &Self) -> Ordering {
        self.key_id.cmp(&other.key_id)
    }
}

impl PartialOrd for PublicKey {
    fn partial_cmp(&self, other: &Self) -> Option<Ordering> {
        Some(self.key_id.cmp(&other.key_id))
    }
}

impl hash::Hash for PublicKey {
    fn hash<H: hash::Hasher>(&self, state: &mut H) {
        // key_id is derived from these fields, so we ignore it.
        self.typ.hash(state);
        self.scheme.hash(state);
        self.keyid_hash_algorithms.hash(state);
        self.value.hash(state);
    }
}

impl Serialize for PublicKey {
    fn serialize<S>(&self, ser: S) -> ::std::result::Result<S::Ok, S::Error>
    where
        S: Serializer,
    {
        let key = shim_public_key(
            &self.typ,
            &self.scheme,
            &self.keyid_hash_algorithms,
            &self.value.0,
        )
        .map_err(|e| SerializeError::custom(format!("Couldn't write key as SPKI: {:?}", e)))?;
        key.serialize(ser)
    }
}

impl<'de> Deserialize<'de> for PublicKey {
    fn deserialize<D: Deserializer<'de>>(de: D) -> ::std::result::Result<Self, D::Error> {
        let intermediate: shims::PublicKey = Deserialize::deserialize(de)?;

        let key = match intermediate.keytype() {
            KeyType::Ed25519 => {
                if intermediate.scheme() != &SignatureScheme::Ed25519 {
                    return Err(DeserializeError::custom(format!(
                        "ed25519 key type must be used with the ed25519 signature scheme, not {:?}",
                        intermediate.scheme()
                    )));
                }

                let bytes = HEXLOWER
                    .decode(intermediate.public_key().as_bytes())
                    .map_err(|e| {
                        DeserializeError::custom(format!("Couldn't parse key as HEX: {:?}", e))
                    })?;

                PublicKey::from_ed25519_with_keyid_hash_algorithms(
                    bytes,
                    intermediate.keyid_hash_algorithms().clone(),
                )
                .map_err(|e| {
                    DeserializeError::custom(format!("Couldn't parse key as ed25519: {:?}", e))
                })?
            }
            KeyType::Unknown(_) => {
                // We don't know this key type, so just leave it as a UTF-8 string.
                PublicKey::new(
                    intermediate.keytype().clone(),
                    intermediate.scheme().clone(),
                    intermediate.keyid_hash_algorithms().clone(),
                    intermediate.public_key().as_bytes().to_vec(),
                )
                .map_err(|e| DeserializeError::custom(format!("Couldn't parse key: {:?}", e)))?
            }
        };

        if intermediate.keytype() != &key.typ {
            return Err(DeserializeError::custom(format!(
                "Key type listed in the metadata did not match the type extrated \
                 from the key. {:?} vs. {:?}",
                intermediate.keytype(),
                key.typ,
            )));
        }

        Ok(key)
    }
}

#[derive(Clone, PartialEq, Hash, Eq)]
struct PublicKeyValue(Vec<u8>);

impl Debug for PublicKeyValue {
    fn fmt(&self, f: &mut fmt::Formatter) -> fmt::Result {
        f.debug_tuple("PublicKeyValue")
            .field(&HEXLOWER.encode(&self.0))
            .finish()
    }
}

/// A structure that contains a `Signature` and associated data for verifying it.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Signature {
    #[serde(rename = "keyid")]
    key_id: KeyId,
    #[serde(rename = "sig")]
    value: SignatureValue,
}

impl Signature {
    /// An immutable reference to the `KeyId` of the key that produced the signature.
    pub fn key_id(&self) -> &KeyId {
        &self.key_id
    }

    /// An immutable reference to the `SignatureValue`.
    pub fn value(&self) -> &SignatureValue {
        &self.value
    }
}

impl PartialOrd for Signature {
    fn partial_cmp(&self, other: &Self) -> Option<Ordering> {
        Some(self.cmp(other))
    }
}

impl Ord for Signature {
    fn cmp(&self, other: &Self) -> Ordering {
        (&self.key_id, &self.value).cmp(&(&other.key_id, &other.value))
    }
}

/// The available hash algorithms.
#[non_exhaustive]
#[derive(Debug, Clone, Hash, PartialEq, Eq, PartialOrd, Ord, Serialize, Deserialize)]
pub enum HashAlgorithm {
    /// SHA256 as describe in [RFC-6234](https://tools.ietf.org/html/rfc6234)
    #[serde(rename = "sha256")]
    Sha256,
    /// SHA512 as describe in [RFC-6234](https://tools.ietf.org/html/rfc6234)
    #[serde(rename = "sha512")]
    Sha512,
    /// Placeholder for an unknown hash algorithm.
    Unknown(String),
}

impl HashAlgorithm {
    /// Create a new `digest::Context` suitable for computing the hash of some data using this hash
    /// algorithm.
    pub(crate) fn digest_context(&self) -> Result<digest::Context> {
        match self {
            HashAlgorithm::Sha256 => Ok(digest::Context::new(&SHA256)),
            HashAlgorithm::Sha512 => Ok(digest::Context::new(&SHA512)),
            HashAlgorithm::Unknown(ref s) => Err(Error::IllegalArgument(format!(
                "Unknown hash algorithm: {}",
                s
            ))),
        }
    }
}

/// Wrapper for the value of a hash digest.
#[derive(Clone, Eq, PartialEq, Hash, Serialize, Deserialize)]
pub struct HashValue(#[serde(with = "crate::format_hex")] Vec<u8>);

impl HashValue {
    /// Create a new `HashValue` from the given digest bytes.
    pub fn new(bytes: Vec<u8>) -> Self {
        HashValue(bytes)
    }

    /// An immutable reference to the bytes of the hash value.
    pub fn value(&self) -> &[u8] {
        &self.0
    }
}

impl Debug for HashValue {
    fn fmt(&self, f: &mut fmt::Formatter) -> fmt::Result {
        f.debug_tuple("HashValue")
            .field(&HEXLOWER.encode(&self.0))
            .finish()
    }
}

impl Display for HashValue {
    fn fmt(&self, f: &mut fmt::Formatter) -> fmt::Result {
        write!(f, "{}", HEXLOWER.encode(&self.0))
    }
}

fn write_spki(public: &[u8], key_type: &KeyType) -> Result<Vec<u8>> {
    let header = match key_type {
        KeyType::Ed25519 => ED25519_SPKI_HEADER,
        KeyType::Unknown(s) => {
            return Err(Error::UnknownKeyType(s.to_owned()));
        }
    };

    let mut output = Vec::with_capacity(header.len() + public.len());
    output.extend_from_slice(header);
    output.extend_from_slice(public);

    Ok(output)
}

#[cfg(test)]
mod test {
    use super::*;
    use assert_matches::assert_matches;
    use pretty_assertions::assert_eq;
    use serde_json::{self, json};

    mod ed25519 {
        pub(super) const PRIVATE_KEY: &[u8] = include_bytes!("../tests/ed25519/ed25519-1");
        pub(super) const PUBLIC_KEY: &[u8] = include_bytes!("../tests/ed25519/ed25519-1.pub");
        pub(super) const PK8_1: &[u8] = include_bytes!("../tests/ed25519/ed25519-1.pk8.der");
        pub(super) const SPKI_1: &[u8] = include_bytes!("../tests/ed25519/ed25519-1.spki.der");
        pub(super) const PK8_2: &[u8] = include_bytes!("../tests/ed25519/ed25519-2.pk8.der");
    }

    #[test]
    fn parse_public_ed25519_spki() {
        let key = PublicKey::from_spki(ed25519::SPKI_1, SignatureScheme::Ed25519).unwrap();
        assert_eq!(key.typ, KeyType::Ed25519);
        assert_eq!(key.scheme, SignatureScheme::Ed25519);
    }

    #[test]
    fn parse_public_ed25519() {
        let key = PublicKey::from_ed25519(ed25519::PUBLIC_KEY).unwrap();
        assert_eq!(
            key.key_id(),
            &KeyId::from_str("e0294a3f17cc8563c3ed5fceb3bd8d3f6bfeeaca499b5c9572729ae015566554")
                .unwrap()
        );
        assert_eq!(key.typ, KeyType::Ed25519);
        assert_eq!(key.scheme, SignatureScheme::Ed25519);
    }

    #[test]
    fn parse_public_ed25519_without_keyid_hash_algo() {
        let key =
            PublicKey::from_ed25519_with_keyid_hash_algorithms(ed25519::PUBLIC_KEY, None).unwrap();
        assert_eq!(
            key.key_id(),
            &KeyId::from_str("e0294a3f17cc8563c3ed5fceb3bd8d3f6bfeeaca499b5c9572729ae015566554")
                .unwrap()
        );
        assert_eq!(key.typ, KeyType::Ed25519);
        assert_eq!(key.scheme, SignatureScheme::Ed25519);
    }

    #[test]
    fn parse_public_ed25519_with_keyid_hash_algo() {
        let key = PublicKey::from_ed25519_with_keyid_hash_algorithms(
            ed25519::PUBLIC_KEY,
            python_tuf_compatibility_keyid_hash_algorithms(),
        )
        .unwrap();
        assert_eq!(
            key.key_id(),
            &KeyId::from_str("a9f3ebc9b138762563a9c27b6edd439959e559709babd123e8d449ba2c18c61a")
                .unwrap(),
        );
        assert_eq!(key.typ, KeyType::Ed25519);
        assert_eq!(key.scheme, SignatureScheme::Ed25519);
    }

    #[test]
    fn ed25519_read_pkcs8_and_sign() {
        let key = Ed25519PrivateKey::from_pkcs8(ed25519::PK8_1).unwrap();
        let msg = b"test";

        let sig = key.sign(msg).unwrap();

        let pub_key =
            PublicKey::from_spki(&key.public.as_spki().unwrap(), SignatureScheme::Ed25519).unwrap();

        let role = MetadataPath::root();
        assert_matches!(pub_key.verify(&role, msg, &sig), Ok(()));

        // Make sure we match what ring expects.
        let ring_key = ring::signature::Ed25519KeyPair::from_pkcs8(ed25519::PK8_1).unwrap();
        assert_eq!(key.public().as_bytes(), ring_key.public_key().as_ref());
        assert_eq!(sig.value().as_bytes(), ring_key.sign(msg).as_ref());

        // Make sure verification fails with the wrong key.
        let bad_pub_key = Ed25519PrivateKey::from_pkcs8(ed25519::PK8_2)
            .unwrap()
            .public()
            .clone();

        assert_matches!(
            bad_pub_key.verify(&role, msg, &sig),
            Err(Error::BadSignature(r))
            if r == role
        );
    }

    #[test]
    fn ed25519_read_keypair_and_sign() {
        let key = Ed25519PrivateKey::from_ed25519(ed25519::PRIVATE_KEY).unwrap();
        let pub_key = PublicKey::from_ed25519(ed25519::PUBLIC_KEY).unwrap();
        assert_eq!(key.public(), &pub_key);

        let role = MetadataPath::root();
        let msg = b"test";
        let sig = key.sign(msg).unwrap();
        assert_matches!(pub_key.verify(&role, msg, &sig), Ok(()));

        // Make sure we match what ring expects.
        let ring_key = ring::signature::Ed25519KeyPair::from_pkcs8(ed25519::PK8_1).unwrap();
        assert_eq!(key.public().as_bytes(), ring_key.public_key().as_ref());
        assert_eq!(sig.value().as_bytes(), ring_key.sign(msg).as_ref());

        // Make sure verification fails with the wrong key.
        let bad_pub_key = Ed25519PrivateKey::from_pkcs8(ed25519::PK8_2)
            .unwrap()
            .public()
            .clone();

        assert_matches!(
            bad_pub_key.verify(&role, msg, &sig),
            Err(Error::BadSignature(r))
            if r == role
        );
    }

    #[test]
    fn ed25519_read_keypair_and_sign_with_keyid_hash_algorithms() {
        let key = Ed25519PrivateKey::from_ed25519_with_keyid_hash_algorithms(
            ed25519::PRIVATE_KEY,
            python_tuf_compatibility_keyid_hash_algorithms(),
        )
        .unwrap();
        let pub_key = PublicKey::from_ed25519_with_keyid_hash_algorithms(
            ed25519::PUBLIC_KEY,
            python_tuf_compatibility_keyid_hash_algorithms(),
        )
        .unwrap();
        assert_eq!(key.public(), &pub_key);

        let role = MetadataPath::root();
        let msg = b"test";
        let sig = key.sign(msg).unwrap();
        assert_matches!(pub_key.verify(&role, msg, &sig), Ok(()));

        // Make sure we match what ring expects.
        let ring_key = ring::signature::Ed25519KeyPair::from_pkcs8(ed25519::PK8_1).unwrap();
        assert_eq!(key.public().as_bytes(), ring_key.public_key().as_ref());
        assert_eq!(sig.value().as_bytes(), ring_key.sign(msg).as_ref());

        // Make sure verification fails with the wrong key.
        let bad_pub_key = Ed25519PrivateKey::from_pkcs8(ed25519::PK8_2)
            .unwrap()
            .public()
            .clone();

        assert_matches!(
            bad_pub_key.verify(&role, msg, &sig),
            Err(Error::BadSignature(r))
            if r == role
        );
    }

    #[test]
    fn unknown_keytype_cannot_verify() {
        let pub_key = PublicKey::new(
            KeyType::Unknown("unknown-keytype".into()),
            SignatureScheme::Unknown("unknown-scheme".into()),
            None,
            b"unknown-key".to_vec(),
        )
        .unwrap();
        let role = MetadataPath::root();
        let msg = b"test";
        let sig = Signature {
            key_id: KeyId("key-id".into()),
            value: SignatureValue(b"sig-value".to_vec()),
        };

        assert_matches!(
            pub_key.verify(&role, msg, &sig),
            Err(Error::UnknownSignatureScheme(s))
            if s == "unknown-scheme"
        );
    }

    #[test]
    fn serde_key_id() {
        let s = "4750eaf6878740780d6f97b12dbad079fb012bec88c78de2c380add56d3f51db";
        let jsn = json!(s);
        let parsed: KeyId = serde_json::from_value(jsn.clone()).unwrap();
        assert_eq!(parsed, KeyId::from_str(s).unwrap());
        let encoded = serde_json::to_value(&parsed).unwrap();
        assert_eq!(encoded, jsn);
    }

    #[test]
    fn serde_key_type() {
        let jsn = json!("ed25519");
        let parsed: KeyType = serde_json::from_value(jsn.clone()).unwrap();
        assert_eq!(parsed, KeyType::Ed25519);

        let encoded = serde_json::to_value(&parsed).unwrap();
        assert_eq!(encoded, jsn);

        let jsn = json!("unknown");
        let parsed: KeyType = serde_json::from_value(jsn).unwrap();
        assert_eq!(parsed, KeyType::Unknown("unknown".into()));
    }

    #[test]
    fn serde_signature_scheme() {
        let jsn = json!("ed25519");
        let parsed: SignatureScheme = serde_json::from_value(jsn.clone()).unwrap();
        assert_eq!(parsed, SignatureScheme::Ed25519);

        let encoded = serde_json::to_value(&parsed).unwrap();
        assert_eq!(encoded, jsn);

        let jsn = json!("unknown");
        let parsed: SignatureScheme = serde_json::from_value(jsn).unwrap();
        assert_eq!(parsed, SignatureScheme::Unknown("unknown".into()));
    }

    #[test]
    fn serde_signature_value() {
        let s = "4750eaf6878740780d6f97b12dbad079fb012bec88c78de2c380add56d3f51db";
        let jsn = json!(s);
        let parsed: SignatureValue = serde_json::from_str(&format!("\"{}\"", s)).unwrap();
        assert_eq!(
            parsed,
            SignatureValue(HEXLOWER.decode(s.as_bytes()).unwrap())
        );
        let encoded = serde_json::to_value(&parsed).unwrap();
        assert_eq!(encoded, jsn);
    }

    #[test]
    fn serde_unknown_keytype_and_signature_scheme_public_key() {
        let pub_key = PublicKey::new(
            KeyType::Unknown("unknown-keytype".into()),
            SignatureScheme::Unknown("unknown-scheme".into()),
            None,
            b"unknown-key".to_vec(),
        )
        .unwrap();
        let encoded = serde_json::to_value(&pub_key).unwrap();
        let jsn = json!({
            "keytype": "unknown-keytype",
            "scheme": "unknown-scheme",
            "keyval": {
                "public": "unknown-key",
            }
        });
        assert_eq!(encoded, jsn);
        let decoded: PublicKey = serde_json::from_value(jsn).unwrap();
        assert_eq!(decoded, pub_key);
    }

    #[test]
    fn serde_ed25519_public_key() {
        let pub_key = Ed25519PrivateKey::from_pkcs8(ed25519::PK8_1)
            .unwrap()
            .public()
            .clone();

        let pub_key = PublicKey::from_ed25519_with_keyid_hash_algorithms(
            pub_key.as_bytes().to_vec(),
            python_tuf_compatibility_keyid_hash_algorithms(),
        )
        .unwrap();
        let encoded = serde_json::to_value(&pub_key).unwrap();
        let jsn = json!({
            "keytype": "ed25519",
            "scheme": "ed25519",
            "keyid_hash_algorithms": ["sha256", "sha512"],
            "keyval": {
                "public": HEXLOWER.encode(pub_key.as_bytes()),
            }
        });
        assert_eq!(encoded, jsn);
        let decoded: PublicKey = serde_json::from_value(encoded).unwrap();
        assert_eq!(decoded, pub_key);
    }

    #[test]
    fn de_ser_ed25519_public_key_with_keyid_hash_algo() {
        let pub_key = Ed25519PrivateKey::from_pkcs8(ed25519::PK8_1)
            .unwrap()
            .public()
            .clone();
        let pub_key = PublicKey::from_ed25519_with_keyid_hash_algorithms(
            pub_key.as_bytes().to_vec(),
            python_tuf_compatibility_keyid_hash_algorithms(),
        )
        .unwrap();
        let original = json!({
            "keytype": "ed25519",
            "scheme": "ed25519",
            "keyid_hash_algorithms": ["sha256", "sha512"],
            "keyval": {
                "public": HEXLOWER.encode(pub_key.as_bytes()),
            }
        });

        let encoded: PublicKey = serde_json::from_value(original.clone()).unwrap();
        #[allow(clippy::needless_borrows_for_generic_args)]
        let decoded = serde_json::to_value(&encoded).unwrap();

        assert_eq!(original, decoded);
    }

    #[test]
    fn de_ser_ed25519_public_key_without_keyid_hash_algo() {
        let pub_key = Ed25519PrivateKey::from_pkcs8(ed25519::PK8_1)
            .unwrap()
            .public()
            .clone();
        let pub_key =
            PublicKey::from_ed25519_with_keyid_hash_algorithms(pub_key.as_bytes().to_vec(), None)
                .unwrap();
        let original = json!({
            "keytype": "ed25519",
            "scheme": "ed25519",
            "keyval": {
                "public": HEXLOWER.encode(pub_key.as_bytes()),
            }
        });

        let encoded: PublicKey = serde_json::from_value(original.clone()).unwrap();
        #[allow(clippy::needless_borrows_for_generic_args)]
        let decoded = serde_json::to_value(&encoded).unwrap();

        assert_eq!(original, decoded);
    }

    #[test]
    fn serde_signature() {
        let key = Ed25519PrivateKey::from_pkcs8(ed25519::PK8_1).unwrap();
        let msg = b"test";
        let sig = key.sign(msg).unwrap();
        let encoded = serde_json::to_value(&sig).unwrap();
        let jsn = json!({
            "keyid": "a9f3ebc9b138762563a9c27b6edd439959e559709babd123e8d449ba2c18c61a",
            "sig": "fe4d13b2a73c033a1de7f5107b205fc7ba0e1566cb95b92349cae6aa453\
                8956013bfe0f7bf977cb072bb65e8782b5f33a0573fe78816299a017ca5ba55\
                9e390c",
        });
        assert_eq!(encoded, jsn);

        let decoded: Signature = serde_json::from_value(encoded).unwrap();
        assert_eq!(decoded, sig);
    }

    #[test]
    fn serde_signature_without_keyid_hash_algo() {
        let key =
            Ed25519PrivateKey::from_pkcs8_with_keyid_hash_algorithms(ed25519::PK8_1, None).unwrap();
        let msg = b"test";
        let sig = key.sign(msg).unwrap();
        let encoded = serde_json::to_value(&sig).unwrap();
        let jsn = json!({
            "keyid": "e0294a3f17cc8563c3ed5fceb3bd8d3f6bfeeaca499b5c9572729ae015566554",
            "sig": "fe4d13b2a73c033a1de7f5107b205fc7ba0e1566cb95b92349cae6aa453\
                    8956013bfe0f7bf977cb072bb65e8782b5f33a0573fe78816299a017ca5ba55\
                    9e390c",
        });
        assert_eq!(encoded, jsn);

        let decoded: Signature = serde_json::from_value(encoded).unwrap();
        assert_eq!(decoded, sig);
    }

    #[test]
    fn new_ed25519_key() {
        let bytes = Ed25519PrivateKey::pkcs8().unwrap();
        let _ = Ed25519PrivateKey::from_pkcs8(&bytes).unwrap();
    }

    #[test]
    fn test_ed25519_public_key_eq() {
        let key1 = Ed25519PrivateKey::from_pkcs8(ed25519::PK8_1).unwrap();
        let key2 = Ed25519PrivateKey::from_pkcs8(ed25519::PK8_2).unwrap();

        assert_eq!(key1.public(), key1.public());
        assert_ne!(key1.public(), key2.public());
    }

    fn check_public_key_hash(key1: &PublicKey, key2: &PublicKey) {
        use std::hash::BuildHasher;

        let state = std::collections::hash_map::RandomState::new();

        assert_ne!(state.hash_one(key1), state.hash_one(key2));
    }

    #[test]
    fn test_ed25519_public_key_hash() {
        let key1 = Ed25519PrivateKey::from_pkcs8(ed25519::PK8_1).unwrap();
        let key2 = Ed25519PrivateKey::from_pkcs8(ed25519::PK8_2).unwrap();

        check_public_key_hash(key1.public(), key2.public());
    }
}
