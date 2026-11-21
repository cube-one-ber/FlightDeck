//! `flightdeck`: live Starship campaign and launch schedule for Omarchy.
//!
//! `flightdeck daemon` keeps `~/.local/share/flightdeck/state.json` current; the
//! bar widget and the Mission Control app read that file and call the other
//! subcommands to change things.

mod alerts;
mod api;
mod config;
mod state;
mod store;
mod text;
mod writer;

use anyhow::{bail, Context, Result};
use chrono::Utc;
use clap::{Parser, Subcommand, ValueEnum};
use config::Config;
use state::{Overrides, State};
use std::io::Write;
use std::path::PathBuf;
use store::{Lock, Paths};
use writer::Writer;

#[derive(Parser)]
#[command(name = "flightdeck", version, about = "Live spaceflight mission control for Omarchy")]
struct Cli {
    /// Config file (default: ~/.config/flightdeck/config.toml).
    #[arg(long, global = true)]
    config: Option<PathBuf>,
    /// Data directory (default: ~/.local/share/flightdeck).
    #[arg(long, global = true)]
    data_dir: Option<PathBuf>,
    #[command(subcommand)]
    cmd: Cmd,
}

#[derive(Subcommand)]
enum Cmd {
    /// Open the Mission Control window.
    Open,
    /// Poll the API and keep state.json current. Run it as a systemd user service.
    Daemon,
    /// Fetch everything now (or ask the running daemon to).
    Sync,
    /// Show the campaign and next launch.
    Status {
        #[arg(long)]
        json: bool,
    },
    /// Force a campaign milestone on or off, or hand it back to the live feed.
    Milestone { id: u32, value: MilestoneValue },
    /// Pin a launch to the bar, or clear the pin with `--clear`.
    Pin {
        id: Option<u32>,
        #[arg(long, conflicts_with = "id")]
        clear: bool,
    },
    /// Print the campaign checklist.
    Checklist {
        /// Copy to the clipboard with wl-copy instead of printing.
        #[arg(long)]
        copy: bool,
    },
    /// Print launches from now through Sunday, in your zones and UTC.
    Weekend {
        #[arg(long)]
        copy: bool,
    },
}

#[derive(Clone, Copy, ValueEnum)]
enum MilestoneValue {
    On,
    Off,
    Auto,
}

fn main() {
    if let Err(e) = run() {
        eprintln!("flightdeck: {e:#}");
        std::process::exit(1);
    }
}

fn run() -> Result<()> {
    let cli = Cli::parse();
    let cfg = Config::load(&cli.config.unwrap_or_else(Config::default_path))?;
    let paths = Paths::new(cli.data_dir.unwrap_or_else(Paths::default_dir));

    match cli.cmd {
        Cmd::Open => open_gui(),
        Cmd::Daemon => {
            let w = Writer::open(cfg, paths, true)?.context("taking the writer lock")?;
            writer::run_daemon(w)
        }
        Cmd::Sync => match Writer::open(cfg, paths.clone(), false)? {
            Some(mut w) => w.sync_once(),
            None => {
                store::write_bytes_atomic(&paths.refresh(), Utc::now().to_rfc3339().as_bytes())?;
                eprintln!("flightdeck: asked the running daemon to refresh");
                Ok(())
            }
        },
        Cmd::Status { json } => {
            let state = read_state(&paths)?;
            if json {
                println!("{}", serde_json::to_string_pretty(&state)?);
            } else {
                print_status(&state);
            }
            Ok(())
        }
        Cmd::Milestone { id, value } => {
            let state = read_state(&paths)?;
            let title = state.campaign.context("no Starship campaign in the feed")?.title;
            update_overrides(cfg, &paths, |o| {
                // Overrides belong to one flight; starting on a new one drops the old set.
                if o.campaign.as_deref() != Some(title.as_str()) {
                    o.milestones.clear();
                    o.campaign = Some(title);
                }
                match value {
                    MilestoneValue::On => o.milestones.insert(id, true),
                    MilestoneValue::Off => o.milestones.insert(id, false),
                    MilestoneValue::Auto => o.milestones.remove(&id),
                };
            })
        }
        Cmd::Pin { id, clear } => {
            if id.is_none() && !clear {
                bail!("give a launch id, or --clear");
            }
            update_overrides(cfg, &paths, |o| o.pinned_launch = id)
        }
        Cmd::Checklist { copy } => {
            let state = read_state(&paths)?;
            let c = state.campaign.as_ref().context("no Starship campaign in the feed")?;
            output(&text::checklist(c), copy)
        }
        Cmd::Weekend { copy } => {
            let state = read_state(&paths)?;
            let mut zones: Vec<chrono_tz::Tz> = cfg
                .timezones
                .iter()
                .map(|z| z.parse().map_err(|_| anyhow::anyhow!("unknown time zone {z:?} in config")))
                .collect::<Result<_>>()?;
            if zones.is_empty() {
                zones.push(text::system_tz());
            }
            output(&text::weekend(&state, &zones, Utc::now()), copy)
        }
    }
}

/// Replaces this process with the Qt window. It is looked up beside this
/// binary first (a dev build), then where the package installs it.
fn open_gui() -> Result<()> {
    use std::os::unix::process::CommandExt;
    let beside = std::env::current_exe()?.with_file_name("flightdeck-gui");
    let gui = [beside, PathBuf::from("/usr/lib/flightdeck/flightdeck-gui")]
        .into_iter()
        .find(|p| p.exists())
        .context("Mission Control (flightdeck-gui) is not installed")?;
    // Tell the window which CLI to call, so a dev build drives this binary, not an installed one.
    let cli = std::env::current_exe()?;
    Err(std::process::Command::new(&gui).env("FLIGHTDECK_CLI", cli).exec()).with_context(|| format!("running {}", gui.display()))
}

fn read_state(paths: &Paths) -> Result<State> {
    store::read_json::<Option<State>>(&paths.state())?
        .context("no state yet: start the daemon (systemctl --user start flightdeck) or run `flightdeck sync`")
}

/// Edits `overrides.json` under its lock. When no daemon is running, this
/// process republishes state itself so the change shows up at once.
fn update_overrides(cfg: Config, paths: &Paths, edit: impl FnOnce(&mut Overrides)) -> Result<()> {
    {
        let _lock = Lock::overrides(paths)?;
        // Starting over from a hand-broken file is better than refusing every change.
        let mut o: Overrides = store::read_json(&paths.overrides()).unwrap_or_else(|e| {
            eprintln!("flightdeck: replacing unreadable overrides: {e:#}");
            Overrides::default()
        });
        edit(&mut o);
        store::write_json_atomic(&paths.overrides(), &o)?;
    }
    if let Some(mut w) = Writer::open(cfg, paths.clone(), false)? {
        w.publish(Utc::now(), false)?;
    }
    Ok(())
}

fn output(text: &str, copy: bool) -> Result<()> {
    if !copy {
        print!("{text}");
        return Ok(());
    }
    // wl-copy forks a server that lives until the clipboard changes; it must
    // not inherit our stdout/stderr, or a caller waiting on them never sees EOF.
    let mut child = std::process::Command::new("wl-copy")
        .stdin(std::process::Stdio::piped())
        .stdout(std::process::Stdio::null())
        .stderr(std::process::Stdio::null())
        .spawn()
        .context("running wl-copy (install wl-clipboard)")?;
    let written = child.stdin.take().unwrap().write_all(text.as_bytes());
    if !child.wait()?.success() {
        bail!("wl-copy failed");
    }
    written?;
    eprintln!("flightdeck: copied {} lines", text.lines().count());
    Ok(())
}

fn print_status(s: &State) {
    let now = Utc::now();
    for (name, src) in &s.sources {
        let stale = src.stale_after.as_deref().is_none_or(|t| t < state::iso(&now).as_str());
        if stale || src.error.is_some() {
            eprintln!(
                "! {name}: last fetched {}{}",
                src.fetched_at.as_deref().unwrap_or("never"),
                src.error.as_deref().map(|e| format!(" ({e})")).unwrap_or_default()
            );
        }
    }
    if let Some(c) = &s.campaign {
        println!("{} · {}/{} milestones", c.title, c.done, c.total);
        for m in c.milestones.iter().filter(|m| m.forced.is_some()) {
            println!("  override #{}: {} → {}{}", m.id, m.title, m.done, if m.diverged { " (live disagrees)" } else { "" });
        }
    }
    if let Some(l) = &s.next {
        let when = match l.t0() {
            Some(t) if l.precision.is_exact() => text::countdown(t, now),
            _ => l.net.clone(),
        };
        println!("Next: {} · {} · {} · {}{}", l.name, l.rocket, l.pad, when, if l.pinned { " (pinned)" } else { "" });
    }
    println!("{} launches in the next window", s.launches.len());
}
