//! Help and banner display utilities for the Morphir CLI.

use owo_colors::{OwoColorize, XtermColors};
use termimad::MadSkin;

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

/// Print Gleam command examples and usage
#[allow(dead_code)]
pub fn print_gleam_help() {
    println!();
    println!("Gleam Language Binding Commands");
    println!("=================================");
    println!();
    println!("The Gleam binding provides frontend (Gleam → Morphir IR) and backend");
    println!("(Morphir IR → Gleam) functionality through the Morphir CLI.");
    println!();
    println!("Examples:");
    println!();
    println!("  # Compile Gleam source to Morphir IR");
    println!("  morphir gleam compile --input src/");
    println!();
    println!("  # Generate Gleam code from Morphir IR");
    println!("  morphir gleam generate --input .morphir/out/<project>/compile/gleam/");
    println!();
    println!("  # Roundtrip test (compile then generate)");
    println!("  morphir gleam roundtrip --input src/");
    println!();
    println!("  # With configuration file (morphir.toml)");
    println!("  morphir gleam compile  # Uses config for paths");
    println!();
    println!("  # JSON output for programmatic use");
    println!("  morphir gleam compile --json");
    println!("  morphir gleam compile --json-lines  # Streaming output");
    println!();
    println!("Configuration:");
    println!();
    println!("  Create a morphir.toml file in your project root:");
    println!();
    println!("    [project]");
    println!("    name = \"my-package\"");
    println!("    source_directory = \"src\"");
    println!();
    println!("    [frontend]");
    println!("    language = \"gleam\"");
    println!();
    println!("Output Structure:");
    println!();
    println!("  IR output:     .morphir/out/<project>/compile/gleam/");
    println!("  Generated code: .morphir/out/<project>/generate/gleam/");
    println!();
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
