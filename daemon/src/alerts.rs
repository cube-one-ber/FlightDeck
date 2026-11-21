//! Desktop alerts: countdown thresholds for every launch with an exact T-0, status changes
//! for launches inside the next day, and milestone or closure changes in the
//! Starship campaign.
//!
//! Everything already fired is saved in `alerts.json`, so restarts never repeat
//! an alert. A threshold key includes T-0, so a slipped launch re-arms itself.

use crate::state::State;
use chrono::{DateTime, Duration, Utc};
use serde::{Deserialize, Serialize};
use std::collections::{BTreeMap, BTreeSet};

/// A threshold alert that is this late (after a suspend, say) is dropped, not sent.
const GRACE_SECS: i64 = 300;

#[derive(Debug, Clone, Default, Serialize, Deserialize, PartialEq)]
#[serde(default)]
pub struct AlertLog {
    /// `launch_id:threshold_min:t0` keys already handled.
    pub fired: BTreeSet<String>,
    pub launch_status: BTreeMap<u32, u32>,
    pub milestones: BTreeMap<u32, bool>,
    /// The campaign `milestones` belong to; ids are reused on the next flight.
    pub campaign: Option<String>,
    /// Closures and TFRs seen, serialized, so a swap of one for another still
    /// counts as new. `None` until the Starship feed has been seen once.
    pub closures: Option<BTreeSet<String>>,
    pub tfrs: Option<BTreeSet<String>>,
}

#[derive(Debug, Clone, PartialEq)]
pub struct Alert {
    pub title: String,
    pub body: String,
    pub urgent: bool,
}

fn threshold_label(min: i64) -> String {
    match min {
        0 => "Liftoff window open".into(),
        m if m % 60 == 0 => format!("T-{} h", m / 60),
        m => format!("T-{m} min"),
    }
}

/// Compares the new state against what was already seen and returns the alerts to send.
pub fn evaluate(state: &State, log: &mut AlertLog, thresholds: &[i64], now: DateTime<Utc>) -> Vec<Alert> {
    let mut out = vec![];

    // Every launch with an exact T-0 gets its thresholds, including the one
    // lifting off right now (it is no longer `next` once T-0 has passed).
    // A launch on Hold (3), scrubbed (4) or already decided (6–9) can keep its
    // old T-0 in the feed; don't count down to it.
    for l in state.launches.iter().filter(|l| l.precision.is_exact() && !matches!(l.status_id, 3 | 4 | 6..=9)) {
        let Some(t0) = l.t0() else { continue };
        for &min in thresholds {
            let at = t0 - Duration::minutes(min);
            let key = format!("{}:{}:{}", l.id, min, l.t0);
            if now >= at && !log.fired.contains(&key) {
                log.fired.insert(key);
                if (now - at).num_seconds() <= GRACE_SECS {
                    out.push(Alert {
                        title: format!("{} · {}", threshold_label(min), l.name),
                        body: [l.rocket.as_str(), l.pad.as_str()]
                            .iter()
                            .filter(|s| !s.is_empty())
                            .copied()
                            .collect::<Vec<_>>()
                            .join(" · "),
                        urgent: min == 0,
                    });
                }
            }
        }
    }
    // Forget thresholds for launches long gone.
    log.fired.retain(|k| {
        let t0 = k.splitn(3, ':').nth(2).unwrap_or("");
        DateTime::parse_from_rfc3339(t0).is_ok_and(|t| now - t.with_timezone(&Utc) < Duration::days(2))
    });

    let soon = now + Duration::hours(24);
    let mut statuses = BTreeMap::new();
    for l in &state.launches {
        let relevant = l.pinned || l.t0().is_some_and(|t| t <= soon);
        if !relevant {
            continue;
        }
        statuses.insert(l.id, l.status_id);
        if let Some(&before) = log.launch_status.get(&l.id) {
            if before != l.status_id && !l.status.is_empty() {
                out.push(Alert {
                    title: format!("{}: {}", l.name, l.status),
                    body: if l.net.is_empty() { l.rocket.clone() } else { l.net.clone() },
                    urgent: matches!(l.status_id, 3 | 4 | 7 | 8 | 9),
                });
            }
        }
    }
    log.launch_status = statuses;

    if let Some(c) = &state.campaign {
        if log.campaign.as_deref() != Some(c.title.as_str()) {
            log.milestones.clear();
            log.campaign = Some(c.title.clone());
        }
        for m in &c.milestones {
            if m.live && log.milestones.get(&m.id) == Some(&false) {
                out.push(Alert { title: format!("{}: ✓ {}", c.short, m.title), body: c.title.clone(), urgent: false });
            }
        }
        log.milestones = c.milestones.iter().map(|m| (m.id, m.live)).collect();
        let closures: BTreeSet<String> = c.closures.iter().map(|v| v.to_string()).collect();
        let tfrs: BTreeSet<String> = c.tfrs.iter().map(|v| v.to_string()).collect();
        // Nothing alerts on first sight: only changes from what was seen before.
        if log.closures.as_ref().is_some_and(|seen| !closures.is_subset(seen)) {
            out.push(Alert { title: format!("{}: new road closure", c.short), body: c.title.clone(), urgent: false });
        }
        if log.tfrs.as_ref().is_some_and(|seen| !tfrs.is_subset(seen)) {
            out.push(Alert { title: format!("{}: new FAA TFR", c.short), body: c.title.clone(), urgent: false });
        }
        log.closures = Some(closures);
        log.tfrs = Some(tfrs);
    }

    out
}

/// Sends an alert through Omarchy's notifier, falling back to `notify-send`.
pub fn send(alert: &Alert) {
    let urgency = if alert.urgent { "critical" } else { "normal" };
    let omarchy = std::process::Command::new("omarchy-notification-send")
        .args(["--app-name", "FlightDeck", "-g", "󱎯", "-u", urgency, &alert.title, &alert.body])
        .status();
    if !matches!(omarchy, Ok(s) if s.success()) {
        let fallback = std::process::Command::new("notify-send")
            .args(["-a", "FlightDeck", "-u", urgency, "--", &alert.title, &alert.body])
            .status();
        if !matches!(fallback, Ok(s) if s.success()) {
            eprintln!("flightdeck: could not deliver alert {:?}", alert.title);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::state::{Bar, Launch, Precision};

    fn t(s: &str) -> DateTime<Utc> {
        DateTime::parse_from_rfc3339(s).unwrap().with_timezone(&Utc)
    }

    fn state_with_next(t0: &str, status_id: u32) -> State {
        let l = Launch {
            id: 7,
            name: "USSF-317".into(),
            provider: "SpaceX".into(),
            rocket: "Falcon 9".into(),
            pad: "SLC-4E".into(),
            location: String::new(),
            t0: t0.into(),
            precision: Precision::Exact,
            net: String::new(),
            status: if status_id == 4 { "Scrub".into() } else { "Go".into() },
            status_id,
            status_color: String::new(),
            pinned: false,
        };
        State {
            schema_version: 1,
            generated_at: String::new(),
            sources: Default::default(),
            campaign: None,
            launches: vec![l.clone()],
            next: Some(l),
            bar: Bar { label: String::new(), t0: None, net: String::new(), progress: String::new(), stale_after: None },
        }
    }

    #[test]
    fn thresholds_fire_once_and_rearm_when_t0_slips() {
        let mut log = AlertLog::default();
        let s = state_with_next("2026-11-20T04:30:00Z", 2);
        assert!(evaluate(&s, &mut log, &[15], t("2026-11-20T04:00:00Z")).is_empty());
        let fired = evaluate(&s, &mut log, &[15], t("2026-11-20T04:15:30Z"));
        assert_eq!(fired.len(), 1);
        assert!(fired[0].title.starts_with("T-15 min"));
        assert!(evaluate(&s, &mut log, &[15], t("2026-11-20T04:16:00Z")).is_empty());

        // A one-hour slip is a new T-0, so the alert fires again at the new time.
        let slipped = state_with_next("2026-11-20T05:30:00Z", 2);
        assert_eq!(evaluate(&slipped, &mut log, &[15], t("2026-11-20T05:15:10Z")).len(), 1);
    }

    #[test]
    fn every_launch_gets_its_thresholds_including_liftoff() {
        use crate::api::{LaunchRow, LaunchStatus, Lookups};
        use crate::state::{derive, Cache, Overrides};
        let mut cache = Cache {
            lookups: Some(Lookups {
                statuses: vec![LaunchStatus { id: 2, name: "Go".into(), color: String::new() }],
                ..Default::default()
            }),
            ..Default::default()
        };
        let row = |id, t0: &str| LaunchRow { id, name: format!("L{id}"), status: 2, t0: Some(t0.into()), ..Default::default() };
        // Two launches 15 minutes apart, ticking every 30 s across both T-0s.
        cache.launches = vec![row(1, "2026-11-20T04:30:00Z"), row(2, "2026-11-20T04:45:00Z")];
        let cfg = crate::config::Config::default();
        let mut log = AlertLog::default();
        let mut titles = vec![];
        let mut now = t("2026-11-20T03:00:00Z");
        while now <= t("2026-11-20T05:00:00Z") {
            let state = derive(&cache, &Overrides::default(), &cfg, now);
            titles.extend(evaluate(&state, &mut log, &[60, 15, 0], now).into_iter().map(|a| a.title));
            now += Duration::seconds(30);
        }
        assert_eq!(
            titles,
            [
                "T-1 h · L1",
                "T-1 h · L2",
                "T-15 min · L1",
                "Liftoff window open · L1",
                "T-15 min · L2",
                "Liftoff window open · L2"
            ]
        );
    }

    #[test]
    fn a_new_flight_does_not_alert_on_reused_milestone_ids() {
        use crate::state::{Campaign, Milestone};
        let campaign = |title: &str, live: bool| Campaign {
            title: title.into(),
            milestones: vec![Milestone { id: 10, title: "Stacked".into(), url: None, live, forced: None, done: live, diverged: false }],
            ..Default::default()
        };
        let mut log = AlertLog::default();
        let mut s = state_with_next("2026-11-20T04:30:00Z", 2);
        let now = t("2026-11-19T00:00:00Z");
        s.campaign = Some(campaign("Starship Flight 16", false));
        evaluate(&s, &mut log, &[], now);
        s.campaign = Some(campaign("Starship Flight 17", true));
        assert!(evaluate(&s, &mut log, &[], now).is_empty());
        s.campaign = Some(campaign("Starship Flight 17", false));
        evaluate(&s, &mut log, &[], now);
        s.campaign = Some(campaign("Starship Flight 17", true));
        assert_eq!(evaluate(&s, &mut log, &[], now).len(), 1);
    }

    #[test]
    fn held_launches_get_no_countdown_alerts() {
        let mut log = AlertLog::default();
        let held = state_with_next("2026-11-20T04:30:00Z", 3);
        assert!(evaluate(&held, &mut log, &[15, 0], t("2026-11-20T04:30:10Z")).is_empty());
    }

    #[test]
    fn missed_thresholds_after_suspend_are_dropped() {
        let mut log = AlertLog::default();
        let s = state_with_next("2026-11-20T04:30:00Z", 2);
        // Waking up 20 minutes after T-60 and T-15 both passed: nothing floods in.
        assert!(evaluate(&s, &mut log, &[60, 15], t("2026-11-20T04:35:00Z")).is_empty());
        assert!(evaluate(&s, &mut log, &[60, 15], t("2026-11-20T04:36:00Z")).is_empty());
    }

    #[test]
    fn status_changes_alert_only_after_first_sight() {
        let mut log = AlertLog::default();
        let now = t("2026-11-20T03:00:00Z");
        assert!(evaluate(&state_with_next("2026-11-20T04:30:00Z", 2), &mut log, &[], now).is_empty());
        let scrub = evaluate(&state_with_next("2026-11-20T04:30:00Z", 4), &mut log, &[], now);
        assert_eq!(scrub.len(), 1);
        assert!(scrub[0].urgent && scrub[0].title.ends_with("Scrub"));
    }
}
