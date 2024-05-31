//use download_git;

fn main() -> Result<(), Box<dyn std::error::Error>> {
    // download_git::download(
    //     "https://github.com/twbs/bootstrap.git:main",
    //     download_git::DownloadOptions {
    //         target_files: Some(vec!["dist".to_string(), "README.md".to_string()]),
    //         dest_path: String::from(TEST_FOLDER),
    //     },
    // )?;
    // git_download::repo("https://github.com/akiradeveloper/lol")
    //     // Tag name can be used.
    //     .branch_name("v0.9.1")
    //     // Can be saved in a different name.
    //     .add_file("lol-core/proto/lol-core.proto", "proto/lol.proto")
    //     .exec()?;

    // tonic_build::configure()
    //     .build_server(false)
    //     .compile(&["lol.proto"], &["proto"])?;

    Ok(())
}
