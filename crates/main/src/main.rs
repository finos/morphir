 use starbase::{system, App, MainResult, State};

 mod settings;
use settings::Settings;

#[derive(Debug,State)]
pub struct Config(Settings);

#[tokio::main]
async fn main() -> MainResult {
    App::setup_diagnostics();
    App::setup_tracing();
    
    let mut app = App::new();
    app.startup(load_config);
    app.run().await?;
    Ok(())
}

#[system]
async fn load_config(states: StatesMut) -> SystemResult {

  let settings = Settings::new()?;
  println!("settings: {:?}", settings);
  
  let config: Config  = Config(settings);
  states.set::<Config>(config);

  ()
}