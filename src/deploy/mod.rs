//! A module for deploying and updating nixos-based validators.

pub use config::{load_configuration, Config, Host};
pub use dry_update::dry_update;
pub use flake::{generate_nixos_flake, NixosFlake};
pub use install::install;
pub use rollback::rollback;
pub use update::update;

mod config;
mod dry_update;
mod flake;
mod install;
mod rollback;
mod update;