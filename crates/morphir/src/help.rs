//! Help and banner display utilities for the Morphir CLI.

use owo_colors::{OwoColorize, XtermColors};
use termimad::MadSkin;

/// Resolve a presentation preference without making help depend on a valid
/// project. Explicit controls also avoid unnecessary configuration I/O.
pub fn banner_enabled<C: clap::CommandFactory>(args: &[String]) -> bool {
    if no_banner_flag::<C>(args) {
        return false;
    }
    if let Some(disabled) = std::env::var("MORPHIR_NO_BANNER")
        .ok()
        .and_then(|value| parse_boolean(&value))
    {
        return !disabled;
    }
    configured_banner().unwrap_or(true)
}

fn parse_boolean(value: &str) -> Option<bool> {
    match value.trim().to_ascii_lowercase().as_str() {
        "true" => Some(true),
        "false" => Some(false),
        _ => None,
    }
}

fn configured_banner() -> Option<bool> {
    let directory = std::env::current_dir().ok()?;
    let project = morphir_devkit::discover_config(&directory).ok()?;
    let effective = morphir_devkit::load_effective_config(
        project.as_deref(),
        &morphir_devkit::ConfigLoadOptions::default(),
    )
    .ok()?;
    effective.value.get("cli")?.get("banner")?.as_bool()
}

/// Clap normally returns before exposing matches for help/version. Use the
/// same argument grammar, but make those actions non-exiting, so a global
/// flag after them is still visible. This preserves option values and `--`.
fn no_banner_flag<C: clap::CommandFactory>(args: &[String]) -> bool {
    let mut command = C::command().disable_help_subcommand(true).subcommand(
        clap::Command::new("help")
            .arg(clap::Arg::new("commands").num_args(0..))
            .arg(
                clap::Arg::new("all")
                    .long("all")
                    .aliases(["full", "experimental"])
                    .action(clap::ArgAction::SetTrue),
            ),
    );
    command.build();
    non_exiting_help(command)
        .try_get_matches_from(args)
        .ok()
        .is_some_and(|matches| matches.get_flag("no_banner"))
}

fn non_exiting_help(command: clap::Command) -> clap::Command {
    command
        .ignore_errors(true)
        .disable_help_subcommand(true)
        .mut_args(|argument| match argument.get_action() {
            clap::ArgAction::Help
            | clap::ArgAction::HelpShort
            | clap::ArgAction::HelpLong
            | clap::ArgAction::Version => argument.action(clap::ArgAction::SetTrue),
            _ => argument,
        })
        .mut_subcommands(non_exiting_help)
}

/// Print the Morphir ASCII art banner with branded colors.
pub fn print_banner() {
    // Morphir brand colors: blue (#00A3E0) and orange (#F26522)
    let blue = XtermColors::from(33); // Bright blue (xterm 33)
    let orange = XtermColors::from(208); // Orange (xterm 208)

    // ASCII art "morphir" with "morph" in blue and "ir" in orange
    println!();
    println!(
        "  {}{}",
        "_ __ ___   ___  _ __ _ __ | |__".color(blue),
        "(_)_ __".color(orange)
    );
    println!(
        " {}{}",
        "| '_ ` _ \\ / _ \\| '__| '_ \\| '_ \\".color(blue),
        "| | '__|".color(orange)
    );
    println!(
        " {}{}",
        "| | | | | | (_) | |  | |_) | | | ".color(blue),
        "| | |".color(orange)
    );
    println!(
        " {}{}",
        "|_| |_| |_|\\___/|_|  | .__/|_| |_".color(blue),
        "|_|_|".color(orange)
    );
    println!("                     {}", "|_|".color(blue));
    println!(
        "  v{} (built {})",
        env!("CARGO_PKG_VERSION"),
        env!("BUILD_DATE")
    );
    println!();
}

/// Print full help including experimental commands.
pub fn print_full_help<C: clap::CommandFactory>() {
    let mut cmd = C::command();
    // Unhide the experimental commands
    for subcommand in cmd.get_subcommands_mut() {
        if subcommand.get_name() == "validate"
            || subcommand.get_name() == "generate"
            || subcommand.get_name() == "transform"
            || subcommand.get_name() == "compile"
            || subcommand.get_name() == "gleam"
        {
            *subcommand = subcommand.clone().hide(false);
        }
    }
    println!("Note: Commands marked [Experimental] are not yet fully implemented.\n");
    cmd.print_help().ok();
}

/// Determine if the banner should be shown based on command-line arguments.
pub fn should_show_banner(args: &[String]) -> bool {
    args.len() == 1
        || args.iter().any(|a| a == "--help" || a == "-h")
        || args.iter().any(|a| a == "--help-all")
        || args.iter().any(|a| a == "--version" || a == "-V")
        || (args.len() == 2 && args.iter().any(|a| a == "help"))
        || should_show_full_help(args)
}

/// Determine if full help (including experimental commands) should be shown.
pub fn should_show_full_help(args: &[String]) -> bool {
    args.iter().any(|a| a == "--help-all")
        || (args.iter().any(|a| a == "help")
            && args
                .iter()
                .any(|a| a == "--all" || a == "--full" || a == "--experimental"))
}

/// Create a styled skin for terminal markdown rendering.
#[allow(dead_code)]
pub fn make_skin() -> MadSkin {
    use termimad::crossterm::style::Color;

    let mut skin = MadSkin::default();

    // Morphir brand colors
    let blue = Color::AnsiValue(33); // Bright blue
    let orange = Color::AnsiValue(208); // Orange

    // Headers in blue
    skin.headers[0].set_fg(blue);
    skin.headers[1].set_fg(blue);
    skin.headers[2].set_fg(blue);

    // Bold/emphasis in orange
    skin.bold.set_fg(orange);

    // Code blocks with background
    skin.code_block.set_bg(Color::AnsiValue(236)); // Dark gray background

    // Inline code styling
    skin.inline_code.set_bg(Color::AnsiValue(236));

    skin
}

/// Print markdown text to the console with syntax highlighting.
#[allow(dead_code)]
pub fn print_markdown(text: &str) {
    let skin = make_skin();
    skin.print_text(text);
}

/// Print markdown text inline (without newline).
#[allow(dead_code)]
pub fn print_markdown_inline(text: &str) {
    let skin = make_skin();
    print!("{}", skin.term_text(text));
}
