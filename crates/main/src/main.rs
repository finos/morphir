 mod settings;
use settings::Settings;

fn main() {
    let settings = Settings::new();
    println!("{:?}", settings);
}