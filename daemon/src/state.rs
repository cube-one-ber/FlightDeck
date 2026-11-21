//! The state model: last-known-good remote facts (`Cache`), user intent
//! (`Overrides`), and the derived `State` that the bar widget and app read.
//!
//! `derive` is pure: the same cache, overrides and clock always give the same
//! state, which keeps the merge rules testable.

use crate::api::{LaunchRow, Lookups, StarshipData, VehicleTest, Video};
use chrono::{DateTime, Datelike, Duration, SecondsFormat, Timelike, Utc};
use serde::{Deserialize, Serialize};
use std::collections::{BTreeMap, HashMap};

pub const SCHEMA_VERSION: u32 = 1;

/// Status ids from `statuses/` that mean the date or time is not set.
const STATUS_TBD_DATE: u32 = 0;
const STATUS_TBD_TIME: u32 = 1;

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(default)]
pub struct SourceMeta {
    pub fetched_at: Option<DateTime<Utc>>,
    pub last_error: Option<String>,
    pub failures: u32,
}

/// Remote facts as last fetched. Kept on disk so a restart or an outage still
/// shows the last good data, marked stale.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(default)]
pub struct Cache {
    pub starship: Option<StarshipData>,
    pub starship_meta: SourceMeta,
    pub launches: Vec<LaunchRow>,
    pub launches_meta: SourceMeta,
    pub lookups: Option<Lookups>,
    pub lookups_meta: SourceMeta,
}

/// What the user asked for. Only the CLI writes this file.
#[derive(Debug, Clone, Default, Serialize, Deserialize, PartialEq)]
#[serde(default)]
pub struct Overrides {
    /// The campaign title the milestone overrides belong to. Milestone ids are
    /// reused from flight to flight, so overrides for another flight are ignored.
    pub campaign: Option<String>,
    /// Milestone id to forced value. Absent means "follow live data".
    pub milestones: BTreeMap<u32, bool>,
    pub pinned_launch: Option<u32>,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "lowercase")]
pub enum Precision {
    Exact,
    Day,
    Month,
    Quarter,
    Half,
    Year,
    Unknown,
}

impl Precision {
    /// Only an exact T-0 gets a ticking countdown or alerts.
    pub fn is_exact(self) -> bool {
        self == Precision::Exact
    }
}

/// Works out how precise a launch time is. TBD launches carry a placeholder
/// T-0 at 23:59:59 on the last day of the period, and the microseconds encode
/// the period: 59 day/month, 70 quarter, 75 half-year, 80 year.
pub fn precision(status: u32, t0: &DateTime<Utc>) -> Precision {
    if status == STATUS_TBD_TIME {
        return Precision::Day;
    }
    if status != STATUS_TBD_DATE {
        return Precision::Exact;
    }
    match t0.nanosecond() / 1000 {
        59 => Precision::Month,
        70 => Precision::Quarter,
        75 => Precision::Half,
        80 => Precision::Year,
        _ => Precision::Unknown,
    }
}

/// A short "when" label for anything without an exact T-0, e.g. "NET Q1 2027".
pub fn net_label(precision: Precision, t0: &DateTime<Utc>) -> String {
    let y = t0.year();
    match precision {
        Precision::Exact => t0.format("%d %b %Y %H:%M UTC").to_string(),
        Precision::Day => t0.format("NET %d %b %Y").to_string(),
        Precision::Month => t0.format("NET %b %Y").to_string(),
        Precision::Quarter => format!("NET Q{} {y}", (t0.month() - 1) / 3 + 1),
        Precision::Half => format!("NET H{} {y}", if t0.month() <= 6 { 1 } else { 2 }),
        Precision::Year => format!("NET {y}"),
        Precision::Unknown => "NET TBD".into(),
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct SourceStatus {
    pub fetched_at: Option<String>,
    pub error: Option<String>,
    /// When this data turns stale. Readers compare it with their own clock, so
    /// a dead daemon still shows as stale. `None` means it was never fetched.
    pub stale_after: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct Milestone {
    pub id: u32,
    pub title: String,
    pub url: Option<String>,
    /// What the live feed says.
    pub live: bool,
    /// The user's forced value, if any.
    pub forced: Option<bool>,
    /// What to show: the forced value when set, otherwise live.
    pub done: bool,
    /// The user's override disagrees with the live feed.
    pub diverged: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct VehicleSummary {
    pub name: String,
    pub kind: String,
    pub status: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct WeatherSummary {
    pub location: String,
    pub summary: String,
    pub temp_c: Option<f64>,
    pub wind_kmh: Option<f64>,
    pub gusts_kmh: Option<f64>,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize, PartialEq)]
pub struct Campaign {
    pub title: String,
    pub short: String,
    pub live_url: Option<String>,
    pub milestones: Vec<Milestone>,
    pub done: usize,
    pub total: usize,
    pub vehicles: Vec<VehicleSummary>,
    pub closures: Vec<serde_json::Value>,
    pub tfrs: Vec<serde_json::Value>,
    pub weather: Option<WeatherSummary>,
    pub recent_tests: Vec<VehicleTest>,
    pub videos: Vec<Video>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct Launch {
    pub id: u32,
    pub name: String,
    pub provider: String,
    pub rocket: String,
    pub pad: String,
    pub location: String,
    pub t0: String,
    pub precision: Precision,
    /// "NET Q1 2027" etc. for inexact dates; empty when exact.
    pub net: String,
    pub status: String,
    pub status_id: u32,
    pub status_color: String,
    pub pinned: bool,
}

impl Launch {
    pub fn t0(&self) -> Option<DateTime<Utc>> {
        DateTime::parse_from_rfc3339(&self.t0).ok().map(|d| d.with_timezone(&Utc))
    }
}

/// What the bar pill shows. The widget ticks the countdown itself from `t0`.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct Bar {
    pub label: String,
    pub t0: Option<String>,
    pub net: String,
    pub progress: String,
    /// The earlier of the Starship and launch sources' `stale_after`.
    pub stale_after: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct State {
    pub schema_version: u32,
    pub generated_at: String,
    pub sources: BTreeMap<String, SourceStatus>,
    pub campaign: Option<Campaign>,
    /// Upcoming launches within the configured window, soonest first.
    pub launches: Vec<Launch>,
    /// The pinned launch, or the soonest with an exact T-0.
    pub next: Option<Launch>,
    pub bar: Bar,
}

pub fn iso(t: &DateTime<Utc>) -> String {
    t.to_rfc3339_opts(SecondsFormat::Secs, true)
}

fn source_status(meta: &SourceMeta, max_age: Duration) -> SourceStatus {
    SourceStatus {
        fetched_at: meta.fetched_at.as_ref().map(iso),
        error: meta.last_error.clone(),
        stale_after: meta.fetched_at.map(|t| iso(&(t + max_age))),
    }
}

/// "Starship Flight 16" becomes "FLT 16"; anything else is kept.
fn short_title(title: &str) -> String {
    match title.rsplit_once("Flight ") {
        Some((_, n)) if !n.is_empty() => format!("FLT {n}"),
        _ => title.to_string(),
    }
}

fn campaign(data: &StarshipData, overrides: &Overrides) -> Option<Campaign> {
    let manager = data.status_manager.as_ref()?;
    let milestones: Vec<Milestone> = data
        .statuses
        .iter()
        .map(|m| {
            let forced = (overrides.campaign.as_deref() == Some(manager.title.as_str()))
                .then(|| overrides.milestones.get(&m.id).copied())
                .flatten();
            Milestone {
                id: m.id,
                title: m.title.clone(),
                url: m.url.clone().filter(|u| !u.is_empty()),
                live: m.confirmed,
                forced,
                done: forced.unwrap_or(m.confirmed),
                diverged: forced.is_some_and(|f| f != m.confirmed),
            }
        })
        .collect();
    let mut vehicles: Vec<_> = data.vehicles.iter().filter(|v| v.status == "Active").collect();
    vehicles.sort_by(|a, b| b.ordering.total_cmp(&a.ordering));
    let mut tests = data.tests.clone();
    tests.sort_by(|a, b| b.date.cmp(&a.date));
    tests.truncate(6);
    let mut videos = data.videos.clone();
    videos.sort_by(|a, b| b.date.cmp(&a.date));
    videos.truncate(5);
    let kmh = |ms: f64| (ms * 3.6 * 10.0).round() / 10.0;
    Some(Campaign {
        title: manager.title.clone(),
        short: short_title(&manager.title),
        live_url: manager.starbase_live.clone().filter(|u| !u.is_empty()),
        done: milestones.iter().filter(|m| m.done).count(),
        total: milestones.len(),
        milestones,
        vehicles: vehicles
            .into_iter()
            .map(|v| VehicleSummary { name: v.name.clone(), kind: v.kind.clone(), status: v.status.clone() })
            .collect(),
        closures: data.closures.clone(),
        tfrs: data.tfrs.clone(),
        weather: data.weather.as_ref().map(|w| WeatherSummary {
            location: w.location.clone(),
            summary: w.weather.clone(),
            temp_c: w.temp.map(|k| ((k - 273.15) * 10.0).round() / 10.0),
            wind_kmh: w.wind.map(kmh),
            gusts_kmh: w.gusts.map(kmh),
        }),
        recent_tests: tests,
        videos,
    })
}

fn launches(cache: &Cache, overrides: &Overrides, window_days: i64, now: DateTime<Utc>) -> Vec<Launch> {
    let none = Lookups::default();
    let lookups = cache.lookups.as_ref().unwrap_or(&none);
    let statuses: HashMap<u32, _> = lookups.statuses.iter().map(|s| (s.id, s)).collect();
    let configs: HashMap<u32, _> = lookups.configs.iter().map(|c| (c.id, c)).collect();
    let agencies: HashMap<u32, _> = lookups.agencies.iter().map(|a| (a.id, a)).collect();
    let pads: HashMap<u32, _> = lookups.pads.iter().map(|p| (p.id, p)).collect();
    // Keep launches that just went up so "In-Flight" stays visible for a while.
    let from = now - Duration::hours(3);
    let until = now + Duration::days(window_days);

    let mut out: Vec<(DateTime<Utc>, Launch)> = cache
        .launches
        .iter()
        .filter_map(|row| {
            let t0 = DateTime::parse_from_rfc3339(row.t0.as_deref()?).ok()?.with_timezone(&Utc);
            // A pin lapses once the launch has dropped out of the window behind.
            let pinned = overrides.pinned_launch == Some(row.id) && t0 >= from;
            if !pinned && (t0 < from || t0 > until) {
                return None;
            }
            let p = precision(row.status, &t0);
            let status = statuses.get(&row.status);
            let pad = row.pad.and_then(|id| pads.get(&id));
            let launch = Launch {
                id: row.id,
                name: row.name.clone(),
                provider: row
                    .agency
                    .and_then(|id| agencies.get(&id))
                    .map(|a| if a.abbrev.is_empty() { a.name.clone() } else { a.abbrev.clone() })
                    .unwrap_or_default(),
                rocket: row.config.and_then(|id| configs.get(&id)).map(|c| c.name.clone()).unwrap_or_default(),
                pad: pad.map(|p| p.name.clone()).unwrap_or_default(),
                location: pad.map(|p| p.location_name.clone()).unwrap_or_default(),
                t0: iso(&t0),
                precision: p,
                net: if p.is_exact() { String::new() } else { net_label(p, &t0) },
                status: status.map(|s| s.name.clone()).unwrap_or_default(),
                status_id: row.status,
                status_color: status.map(|s| s.color.clone()).unwrap_or_default(),
                pinned,
            };
            Some((t0, launch))
        })
        .collect();
    out.sort_by(|a, b| a.0.cmp(&b.0).then(a.1.id.cmp(&b.1.id)));
    out.into_iter().map(|(_, l)| l).collect()
}

/// Builds the state the UIs read from the cache, the user's overrides and the clock.
pub fn derive(cache: &Cache, overrides: &Overrides, cfg: &crate::config::Config, now: DateTime<Utc>) -> State {
    let mut sources = BTreeMap::new();
    let max_age = |poll: u64, times: u64, floor: i64| {
        Duration::seconds(i64::try_from(poll.saturating_mul(times)).unwrap_or(i64::MAX).clamp(floor, 7 * 86400))
    };
    sources.insert("starship".into(), source_status(&cache.starship_meta, max_age(cfg.starship_poll_secs, 5, 300)));
    sources.insert("launches".into(), source_status(&cache.launches_meta, max_age(cfg.launches_poll_secs, 3, 3600)));
    sources.insert("lookups".into(), source_status(&cache.lookups_meta, Duration::days(3)));

    let campaign = cache.starship.as_ref().and_then(|d| campaign(d, overrides));
    let launches = launches(cache, overrides, cfg.window_days, now);
    let next = launches
        .iter()
        .find(|l| l.pinned)
        // A launch stays `next` for a few minutes after T-0, so the bar shows T+ at
        // liftoff. A scrub (4) or prelaunch failure (9) may keep its stale T-0, so it never leads the bar.
        .or_else(|| {
            launches.iter().find(|l| {
                l.precision.is_exact() && !matches!(l.status_id, 4 | 9) && l.t0().is_some_and(|t| t > now - Duration::minutes(10))
            })
        })
        .cloned();

    // ISO timestamps in one format sort as strings; never-fetched (None) sorts first.
    let stale_after = sources.values().map(|s| s.stale_after.clone()).min().flatten();
    let progress = campaign.as_ref().map(|c| format!("{} {}/{}", c.short, c.done, c.total)).unwrap_or_default();
    let bar = match &next {
        Some(l) => Bar {
            label: short_launch_name(l),
            t0: l.precision.is_exact().then(|| l.t0.clone()),
            net: l.net.clone(),
            progress,
            stale_after,
        },
        None => Bar { label: String::new(), t0: None, net: String::new(), progress, stale_after },
    };

    State {
        schema_version: SCHEMA_VERSION,
        generated_at: iso(&now),
        sources,
        campaign,
        launches,
        next,
        bar,
    }
}

/// A compact name for the bar: the rocket when known, else the launch name.
fn short_launch_name(l: &Launch) -> String {
    let name = if l.rocket.is_empty() { &l.name } else { &l.rocket };
    // Long March vehicles go by their Chinese designation, "CZ-8A".
    let name = match name.strip_prefix("Long March ") {
        Some(model) => format!("CZ-{model}"),
        None => name.to_string(),
    };
    name.replace(" Block 5", "").replace("Falcon 9", "F9").replace("Falcon Heavy", "FH")
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::api::{LaunchStatus, RemoteMilestone, StatusManager};
    use crate::config::Config;

    fn t(s: &str) -> DateTime<Utc> {
        DateTime::parse_from_rfc3339(s).unwrap().with_timezone(&Utc)
    }

    #[test]
    fn decodes_tbd_precision_from_placeholder_timestamps() {
        assert_eq!(precision(2, &t("2026-11-20T04:32:55Z")), Precision::Exact);
        assert_eq!(precision(1, &t("2026-11-25T23:59:59.000059Z")), Precision::Day);
        assert_eq!(precision(0, &t("2026-11-30T23:59:59.000059Z")), Precision::Month);
        assert_eq!(precision(0, &t("2027-03-31T23:59:59.000070Z")), Precision::Quarter);
        assert_eq!(precision(0, &t("2027-06-30T23:59:59.000075Z")), Precision::Half);
        assert_eq!(precision(0, &t("2027-12-31T23:59:59.000080Z")), Precision::Year);
        assert_eq!(net_label(Precision::Quarter, &t("2027-03-31T23:59:59Z")), "NET Q1 2027");
        assert_eq!(net_label(Precision::Half, &t("2027-12-31T23:59:59Z")), "NET H2 2027");
    }

    fn cache_with_milestones(live: &[(u32, bool)]) -> Cache {
        Cache {
            starship: Some(StarshipData {
                status_manager: Some(StatusManager { id: 2, title: "Starship Flight 16".into(), starbase_live: None }),
                statuses: live
                    .iter()
                    .map(|&(id, confirmed)| RemoteMilestone { id, title: format!("m{id}"), confirmed, url: None })
                    .collect(),
                ..Default::default()
            }),
            ..Default::default()
        }
    }

    #[test]
    fn overrides_stay_separate_from_live_facts() {
        let cache = cache_with_milestones(&[(1, true), (2, false), (3, false)]);
        let mut ov = Overrides { campaign: Some("Starship Flight 16".into()), ..Default::default() };
        ov.milestones.insert(2, true); // user marks it done before the feed does
        ov.milestones.insert(1, true); // redundant: live already agrees
        let s = derive(&cache, &ov, &Config::default(), t("2026-11-19T00:00:00Z"));
        let c = s.campaign.unwrap();
        assert_eq!((c.short.as_str(), c.done, c.total), ("FLT 16", 2, 3));
        let m2 = &c.milestones[1];
        assert!(m2.done && !m2.live && m2.diverged);
        let m1 = &c.milestones[0];
        assert!(m1.done && m1.forced == Some(true) && !m1.diverged);
        assert_eq!(s.bar.progress, "FLT 16 2/3");

        // The next flight reuses milestone ids; Flight 16's overrides must not carry over.
        let mut next = cache.clone();
        next.starship.as_mut().unwrap().status_manager.as_mut().unwrap().title = "Starship Flight 17".into();
        let c = derive(&next, &ov, &Config::default(), t("2026-11-19T00:00:00Z")).campaign.unwrap();
        assert!(c.milestones.iter().all(|m| m.forced.is_none()));
        assert_eq!(c.done, 1);
    }

    #[test]
    fn next_launch_skips_inexact_dates_unless_pinned() {
        let now = t("2026-11-19T00:00:00Z");
        let mut cache = Cache {
            lookups: Some(Lookups {
                statuses: vec![LaunchStatus { id: 2, name: "Go".into(), color: "#7ED47E".into() }],
                ..Default::default()
            }),
            ..Default::default()
        };
        let row = |id, s, t0: &str| LaunchRow { id, name: format!("L{id}"), status: s, t0: Some(t0.into()), ..Default::default() };
        cache.launches = vec![
            row(1, 0, "2026-11-30T23:59:59.000059Z"),
            row(2, 2, "2026-11-20T04:32:55Z"),
            row(3, 2, "2025-01-01T00:00:00Z"), // long past: dropped
        ];
        let s = derive(&cache, &Overrides::default(), &Config::default(), now);
        assert_eq!(s.launches.iter().map(|l| l.id).collect::<Vec<_>>(), vec![2, 1]);
        assert_eq!(s.next.as_ref().unwrap().id, 2);
        assert_eq!(s.bar.t0.as_deref(), Some("2026-11-20T04:32:55Z"));
        assert_eq!(s.bar.stale_after, None, "never-fetched sources must read as stale");

        let ov = Overrides { pinned_launch: Some(1), ..Default::default() };
        let s = derive(&cache, &ov, &Config::default(), now);
        let next = s.next.unwrap();
        assert_eq!((next.id, next.net.as_str()), (1, "NET Nov 2026"));
        assert_eq!(s.bar.t0, None, "no fake countdown for a month-level date");
    }
}
