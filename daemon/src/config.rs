//! User configuration, read from `~/.config/flightdeck/config.toml`.
//! Every field is optional; unknown keys are ignored so old configs keep working.

use anyhow::{Context, Result};
use serde::Deserialize;
use std::path::{Path, PathBuf};

#[derive(Debug, Clone, Deserialize)]
#[serde(default)]
pub struct Config {
    pub base_url: String,
    pub starship_poll_secs: u64,
    pub launches_poll_secs: u64,
    /// How far ahead the schedule looks.
    pub window_days: i64,
    /// Countdown alerts, in minutes before T-0 (0 means liftoff).
    pub alert_minutes: Vec<i64>,
    /// Extra zones shown in copied slates, beside UTC. Empty means the system zone.
    pub timezones: Vec<String>,
    pub notifications: bool,
}

impl Default for Config {
    fn default() -> Self {
        Self {
            base_url: "https://api.nextspaceflight.com/api/".into(),
            starship_poll_secs: 60,
            launches_poll_secs: 300,
            window_days: 30,
            alert_minutes: vec![60, 15, 0],
            timezones: vec![],
            notifications: true,
        }
    }
}

impl Config {
    /// Loads the config, falling back to defaults when the file is missing.
    pub fn load(path: &Path) -> Result<Self> {
        let mut cfg: Config = match std::fs::read_to_string(path) {
            Ok(text) => toml::from_str(&text).with_context(|| format!("parsing {}", path.display()))?,
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => Config::default(),
            Err(e) => return Err(e).with_context(|| format!("reading {}", path.display())),
        };
        if !cfg.base_url.ends_with('/') {
            cfg.base_url.push('/');
        }
        Ok(cfg)
    }

    pub fn default_path() -> PathBuf {
        config_dir().join("flightdeck/config.toml")
    }
}

fn config_dir() -> PathBuf {
    std::env::var_os("XDG_CONFIG_HOME")
        .filter(|d| !d.is_empty())
        .map(PathBuf::from)
        .unwrap_or_else(|| home().join(".config"))
}

pub fn home() -> PathBuf {
    std::env::var_os("HOME").map(PathBuf::from).unwrap_or_else(|| PathBuf::from("/"))
}
