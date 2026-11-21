//! The single writer of `cache.json`, `state.json` and `alerts.json`, used by
//! the daemon loop and by one-shot CLI commands when no daemon is running.

use crate::alerts::{self, AlertLog};
use crate::api::Client;
use crate::config::Config;
use crate::state::{self, Cache, Overrides, SourceMeta, State};
use crate::store::{self, Lock, Paths};
use anyhow::Result;
use chrono::{DateTime, Utc};
use std::time::{Duration, SystemTime};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Source {
    Starship,
    Launches,
    Lookups,
}

pub struct Writer {
    pub cfg: Config,
    pub paths: Paths,
    client: Client,
    pub cache: Cache,
    overrides: Overrides,
    overrides_seen: Option<(SystemTime, u64)>,
    log: AlertLog,
    last: Option<State>,
    _lock: Lock,
}

impl Writer {
    /// Takes the writer lock. Returns `None` when another process holds it,
    /// unless `wait` is set (the daemon), which waits out a one-shot command.
    pub fn open(cfg: Config, paths: Paths, wait: bool) -> Result<Option<Writer>> {
        let lock = if wait { Some(Lock::writer(&paths)?) } else { Lock::try_writer(&paths)? };
        let Some(lock) = lock else { return Ok(None) };
        // A corrupt cache or log is not worth refusing to start over.
        let cache = store::read_json(&paths.cache()).unwrap_or_else(|e| {
            eprintln!("flightdeck: ignoring unreadable cache: {e:#}");
            Cache::default()
        });
        let log = store::read_json(&paths.alerts()).unwrap_or_else(|e| {
            eprintln!("flightdeck: ignoring unreadable alert log: {e:#}");
            AlertLog::default()
        });
        let last = store::read_json::<Option<State>>(&paths.state()).ok().flatten();
        let client = Client::new(&cfg)?;
        let mut w = Writer {
            cfg,
            paths,
            client,
            cache,
            overrides: Overrides::default(),
            overrides_seen: None,
            log,
            last,
            _lock: lock,
        };
        // A hand-broken overrides.json must not keep the daemon from starting.
        if let Err(e) = w.reload_overrides() {
            eprintln!("flightdeck: ignoring unreadable overrides: {e:#}");
        }
        Ok(Some(w))
    }

    /// Re-reads `overrides.json` if it changed. Returns true when it did.
    pub fn reload_overrides(&mut self) -> Result<bool> {
        // Every save is a rename, so a new inode marks a change even within one mtime tick.
        let seen = store::identity(&self.paths.overrides());
        if seen == self.overrides_seen {
            return Ok(false);
        }
        // Record the seen identity before parsing so a hand-broken overrides.json
        // logs once per file change instead of every daemon tick; atomic renames
        // will give a new inode/mtime when fixed.
        self.overrides_seen = seen;
        let next: Overrides = store::read_json(&self.paths.overrides())?;
        let changed = next != self.overrides;
        self.overrides = next;
        Ok(changed)
    }

    pub fn meta(&self, source: Source) -> &SourceMeta {
        match source {
            Source::Starship => &self.cache.starship_meta,
            Source::Launches => &self.cache.launches_meta,
            Source::Lookups => &self.cache.lookups_meta,
        }
    }

    /// Fetches one source. On failure the last good data stays and the error is recorded.
    pub fn poll(&mut self, source: Source) -> Result<()> {
        let now = Utc::now();
        let result = match source {
            Source::Starship => self.client.starship().map(|d| self.cache.starship = Some(d)),
            Source::Launches => self.client.launches().map(|mut d| {
                // The feed reaches back years; only recent and future rows matter.
                let cutoff = now - chrono::Duration::days(1);
                d.retain(|r| {
                    r.t0.as_deref()
                        .and_then(|t| DateTime::parse_from_rfc3339(t).ok())
                        .is_some_and(|t| t >= cutoff)
                });
                self.cache.launches = d
            }),
            Source::Lookups => self.client.lookups().map(|d| self.cache.lookups = Some(d)),
        };
        let meta = match source {
            Source::Starship => &mut self.cache.starship_meta,
            Source::Launches => &mut self.cache.launches_meta,
            Source::Lookups => &mut self.cache.lookups_meta,
        };
        match &result {
            Ok(()) => {
                meta.fetched_at = Some(now);
                meta.last_error = None;
                meta.failures = 0;
            }
            Err(e) => {
                meta.last_error = Some(format!("{e:#}"));
                meta.failures = meta.failures.saturating_add(1);
            }
        }
        store::write_json_atomic(&self.paths.cache(), &self.cache)?;
        result
    }

    /// Derives the state and writes `state.json` if it changed. Only the daemon
    /// passes `alerts`; one-shot commands leave the alert log for it untouched.
    pub fn publish(&mut self, now: DateTime<Utc>, alerts: bool) -> Result<&State> {
        // Pick up an override saved while this process was busy polling.
        if let Err(e) = self.reload_overrides() {
            eprintln!("flightdeck: overrides: {e:#}");
        }
        let state = state::derive(&self.cache, &self.overrides, &self.cfg, now);
        if alerts {
            let log_before = self.log.clone();
            let due = alerts::evaluate(&state, &mut self.log, &self.cfg.alert_minutes, now);
            if self.cfg.notifications {
                for a in &due {
                    alerts::send(a);
                }
            }
            // A failed write only risks a repeat after a restart; keep running.
            if self.log != log_before {
                if let Err(e) = store::write_json_atomic(&self.paths.alerts(), &self.log) {
                    eprintln!("flightdeck: saving alert log: {e:#}");
                }
            }
        }
        // `generated_at` changes every call; only rewrite when something else did.
        let same = self.last.as_ref().is_some_and(|prev| {
            let mut a = prev.clone();
            a.generated_at = state.generated_at.clone();
            a == state
        });
        if !same {
            store::write_json_atomic(&self.paths.state(), &state)?;
        }
        Ok(self.last.insert(state))
    }

    /// Polls every source once and publishes without sending alerts.
    pub fn sync_once(&mut self) -> Result<()> {
        let mut errors = vec![];
        for s in [Source::Lookups, Source::Launches, Source::Starship] {
            if let Err(e) = self.poll(s) {
                errors.push(format!("{s:?}: {e:#}"));
            }
        }
        self.publish(Utc::now(), false)?;
        if errors.is_empty() {
            Ok(())
        } else {
            anyhow::bail!("{}", errors.join("\n"))
        }
    }
}

/// The base interval for each source.
fn interval(cfg: &Config, s: Source) -> Duration {
    Duration::from_secs(match s {
        Source::Starship => cfg.starship_poll_secs.clamp(15, 86400),
        Source::Launches => cfg.launches_poll_secs.clamp(60, 86400),
        Source::Lookups => 24 * 3600,
    })
}

/// Next delay after a poll: the interval when healthy. After a failure, retries
/// start at a minute at most (sooner than a long healthy interval) and double
/// per failure up to 15 minutes (or the interval if longer), plus some jitter.
fn next_delay(cfg: &Config, s: Source, failures: u32) -> Duration {
    let base = interval(cfg, s);
    if failures == 0 {
        return base;
    }
    let cap = base.max(Duration::from_secs(900));
    let backoff = base.min(Duration::from_secs(60)) * 2u32.saturating_pow(failures.min(8));
    let jitter = Duration::from_millis(u64::from(SystemTime::now().duration_since(SystemTime::UNIX_EPOCH).unwrap_or_default().subsec_millis()) * 10);
    backoff.min(cap) + jitter
}

/// Runs forever: polls on schedule, follows overrides and refresh requests,
/// and republishes every couple of seconds so countdown alerts fire on time.
pub fn run_daemon(mut w: Writer) -> Result<()> {
    let sources = [Source::Lookups, Source::Launches, Source::Starship];
    let index = |s: Source| sources.iter().position(|&x| x == s).unwrap();
    // The schedule runs on the wall clock: a monotonic clock stops during
    // suspend, which would leave data stale for a whole interval after wake.
    // Fresh cached data needn't be refetched straight after a restart.
    let mut due: Vec<DateTime<Utc>> = sources
        .iter()
        .map(|&s| w.meta(s).fetched_at.map_or_else(Utc::now, |t| t + chrono_delay(interval(&w.cfg, s))))
        .collect();
    eprintln!("flightdeck: daemon started, writing {}", w.paths.state().display());

    loop {
        // `flightdeck sync` drops a refresh file; consuming it makes each request count once.
        match std::fs::remove_file(w.paths.refresh()) {
            Ok(()) => {
                for s in sources {
                    // Lookups change rarely; refetch them only when they're missing or failing.
                    if s != Source::Lookups || w.cache.lookups.is_none() || w.meta(s).failures > 0 {
                        due[index(s)] = Utc::now();
                    }
                }
            }
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => {}
            Err(e) => eprintln!("flightdeck: refresh request: {e:#}"),
        }
        // Publish around each poll, so a slow request delays alerts and
        // overrides by one request at most.
        w.publish(Utc::now(), true)?;
        for (i, &s) in sources.iter().enumerate() {
            if Utc::now() >= due[i] {
                if let Err(e) = w.poll(s) {
                    eprintln!("flightdeck: {s:?} poll failed: {e:#}");
                }
                due[i] = Utc::now() + chrono_delay(next_delay(&w.cfg, s, w.meta(s).failures));
                w.publish(Utc::now(), true)?;
            }
        }
        std::thread::sleep(Duration::from_secs(2));
    }
}

fn chrono_delay(d: Duration) -> chrono::Duration {
    chrono::Duration::from_std(d).unwrap_or(chrono::Duration::days(1))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn backoff_grows_and_caps() {
        let cfg = Config::default();
        assert_eq!(next_delay(&cfg, Source::Starship, 0), Duration::from_secs(60));
        let one = next_delay(&cfg, Source::Starship, 1);
        assert!(one >= Duration::from_secs(120) && one < Duration::from_secs(131));
        let many = next_delay(&cfg, Source::Starship, 30);
        assert!(many >= Duration::from_secs(900) && many < Duration::from_secs(911));
    }
}
