use std::env;
#[allow(dead_code)]
use std::path::PathBuf;

use anyhow::Result;
use clap::{Parser, Subcommand};

extern crate self as moderator;
mod config;
mod create;

#[derive(Parser)]
#[command(name = "Moderator")]
#[command(version = "0.1")]
#[command(about = "EC4X Game Moderator", long_about = None)]
struct Args {
    #[command(subcommand)]
    command: Commands,
}

#[derive(Subcommand)]
enum Commands {
    /// Initialize a new game in <DIR>
    New { dir: PathBuf },
    /// Start the server for game located at <DIR>
    Start { _dir: PathBuf },
    /// Run turn maintenance on game located at <DIR>
    Maint { _dir: PathBuf },
    /// Display game stastics for game located at <DIR>
    Stats { _dir: PathBuf },
}

fn parse_args(args: Args) -> Result<()> {
    match &args.command {
        Commands::New { dir } => create::new_game(dir),
        Commands::Start { _dir } => Ok(()),
        Commands::Maint { _dir } => Ok(()),
        Commands::Stats { _dir } => Ok(()),
    }
}

fn main() -> Result<()> {
    env::set_var("RUST_BACKTRACE", "1");
    parse_args(Args::parse())
}
