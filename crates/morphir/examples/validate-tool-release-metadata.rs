use morphir_distribution::ToolReleaseRecord;
use std::io::{Error, ErrorKind};
use std::path::Path;

fn validate(path: &Path) -> Result<(), Error> {
    let bytes = std::fs::read(path)?;
    serde_json::from_slice::<ToolReleaseRecord>(&bytes)
        .map(|_| ())
        .map_err(|source| {
            Error::new(
                ErrorKind::InvalidData,
                format!("{}: {source}", path.display()),
            )
        })
}

fn main() -> Result<(), Error> {
    let paths = std::env::args_os().skip(1).collect::<Vec<_>>();
    if paths.is_empty() {
        return Err(Error::new(
            ErrorKind::InvalidInput,
            "expected at least one release descriptor path",
        ));
    }

    paths.iter().try_for_each(|path| validate(Path::new(path)))
}
