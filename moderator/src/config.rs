use std::path::PathBuf;
use std::fs;
use anyhow::{anyhow, Context, Result};

use std::process::exit;

use toml;
use serde::Deserialize;

/// Game configuration file
const CONFIG_FILE: &str = "game_config.toml";

#[derive(Deserialize)]
pub struct Config {
    pub host_name: String,
    pub game_name: String,
    pub server_ip: String,
    pub port: String,
    pub num_empires: u32,
}

fn check_game_path(dir: PathBuf) -> Result<()> {
    let attr = fs::metadata(&dir)
        .with_context(|| format!("Invalid path `{}`", dir.display()))?;
    if !attr.is_dir() {
        return Err(anyhow!("Given path is not a directory"));
    }
    Ok(())   
}

pub fn load_config(mut game_path: PathBuf) -> Result<Config> {
    check_game_path(game_path.clone())?;
    
    game_path.push(CONFIG_FILE);
    
    // Read the contents of the file
    let contents = match fs::read_to_string(game_path.clone()) {
        Ok(c) => c,
        Err(_) => {
            eprintln!("Error: Could not read {CONFIG_FILE}");
            exit(1);
        }
    };

    // Load toml file contents in Config structure
    let config: Config = match toml::from_str(&contents) {
        Ok(d) => d,
        Err(_) => {
            eprintln!("Error: Unable to load data from {CONFIG_FILE}");
            exit(1);
        }
    };

    // check for minimum number of players
    if config.num_empires < 2 {
        eprintln!("Error: Minimum number of players is two");
        exit(1);
    }

    // TODO: Make this a LOG message
    println!("\nLoaded config file {}", game_path.display());
    println!("Host Name: {}", config.host_name);
    println!("Game Name: {}", config.game_name);
    println!("Server IP: {}", config.server_ip);
    println!("Port: {}", config.port);
    println!("Num Empires: {}", config.num_empires);

    Ok(config)
}
