//! Plain-text output: countdowns, the campaign checklist and the launch slate,
//! formatted for the terminal and for pasting into a post.

use crate::state::{Campaign, Launch, Precision, State};
use chrono::{DateTime, Datelike, Duration, Offset, TimeZone, Utc, Weekday};
use chrono_tz::Tz;

/// `T-02:14:09`, `T-3d 04:12`, or `T+00:01:12` once T-0 has passed.
pub fn countdown(t0: DateTime<Utc>, now: DateTime<Utc>) -> String {
    let secs = (t0 - now).num_seconds();
    let (sign, s) = if secs >= 0 { ('-', secs) } else { ('+', -secs) };
    let (d, h, m, s) = (s / 86400, s / 3600 % 24, s / 60 % 60, s % 60);
    if d > 0 {
        format!("T{sign}{d}d {h:02}:{m:02}")
    } else {
        format!("T{sign}{h:02}:{m:02}:{s:02}")
    }
}

pub fn checklist(c: &Campaign) -> String {
    let mut out = format!("{} · {}/{} milestones\n", c.title, c.done, c.total);
    for m in &c.milestones {
        out.push_str(if m.done { "✓ " } else { "☐ " });
        out.push_str(&m.title);
        out.push('\n');
    }
    out
}

/// The system's IANA zone from `$TZ` or `/etc/localtime`, else UTC.
pub fn system_tz() -> Tz {
    let name = std::env::var("TZ").ok().filter(|z| !z.is_empty()).or_else(|| {
        std::fs::read_link("/etc/localtime")
            .ok()
            .and_then(|p| p.to_str().and_then(|s| s.split("zoneinfo/").nth(1)).map(str::to_string))
    });
    name.and_then(|n| n.trim_start_matches(':').parse().ok()).unwrap_or(Tz::UTC)
}

/// "20:32 PST", with the weekday added when this zone is on another date than the headline.
fn stamp<Z: TimeZone>(t: DateTime<Z>, headline: &chrono::NaiveDate) -> String
where
    Z::Offset: std::fmt::Display,
{
    let fmt = if t.date_naive() == *headline { "%H:%M %Z" } else { "%a %H:%M %Z" };
    t.format(fmt).to_string()
}

/// The end of the coming Sunday in `tz`, so "this weekend" means through Sunday night.
pub fn end_of_weekend(now: DateTime<Utc>, tz: Tz) -> DateTime<Utc> {
    let local = now.with_timezone(&tz).date_naive();
    let days = (Weekday::Sun.num_days_from_monday() + 7 - local.weekday().num_days_from_monday()) % 7;
    let sunday = local + Duration::days(days as i64);
    tz.from_local_datetime(&sunday.and_hms_opt(23, 59, 59).unwrap())
        .earliest()
        .map(|d| d.with_timezone(&Utc))
        .unwrap_or(now + Duration::days(days as i64 + 1))
}

/// Launches from now through Sunday, each with times in `zones` and UTC.
pub fn weekend(state: &State, zones: &[Tz], now: DateTime<Utc>) -> String {
    let home = zones.first().copied().unwrap_or(Tz::UTC);
    let until = end_of_weekend(now, home);
    let mut out = format!("🚀 Rockets through {}\n\n", until.with_timezone(&home).format("%a %d %b"));
    let upcoming: Vec<&Launch> = state
        .launches
        .iter()
        .filter(|l| match (l.precision, l.t0()) {
            (Precision::Exact, Some(t)) => t >= now - Duration::hours(1) && t <= until,
            // A day-only launch carries 23:59:59 UTC on its date; compare the date itself.
            (Precision::Day, Some(t)) => {
                (now.with_timezone(&home).date_naive()..=until.with_timezone(&home).date_naive()).contains(&t.date_naive())
            }
            // Month, quarter and year placeholders say nothing about this weekend.
            _ => false,
        })
        .collect();
    if upcoming.is_empty() {
        out.push_str("No launches scheduled.\n");
    }
    for l in upcoming {
        let t0 = l.t0().unwrap();
        let home_date = t0.with_timezone(&home).date_naive();
        let when = if l.precision.is_exact() {
            let mut parts: Vec<String> = zones
                .iter()
                .map(|z| t0.with_timezone(z))
                // A zone sitting on UTC (London in winter) would just repeat the UTC time.
                .filter(|local| local.offset().fix().local_minus_utc() != 0)
                .map(|local| stamp(local, &home_date))
                .collect();
            parts.push(stamp(t0, &home_date));
            format!("{} {}", t0.with_timezone(&home).format("%a %d %b"), parts.join(" / "))
        } else {
            l.net.clone()
        };
        let what: Vec<&str> = [l.rocket.as_str(), l.name.as_str(), l.pad.as_str()]
            .into_iter()
            .filter(|s| !s.is_empty())
            .collect();
        out.push_str(&format!("{when}\n  {}", what.join(" · ")));
        if !l.status.is_empty() && l.status != "Go" {
            out.push_str(&format!(" ({})", l.status));
        }
        out.push_str("\n\n");
    }
    out.trim_end().to_string() + "\n"
}

#[cfg(test)]
mod tests {
    use super::*;

    fn t(s: &str) -> DateTime<Utc> {
        DateTime::parse_from_rfc3339(s).unwrap().with_timezone(&Utc)
    }

    #[test]
    fn countdown_formats() {
        let now = t("2026-11-20T00:00:00Z");
        assert_eq!(countdown(t("2026-11-20T02:14:09Z"), now), "T-02:14:09");
        assert_eq!(countdown(t("2026-11-23T04:12:00Z"), now), "T-3d 04:12");
        assert_eq!(countdown(t("2026-11-19T23:58:48Z"), now), "T+00:01:12");
    }

    #[test]
    fn weekend_runs_through_sunday_night_local() {
        let london: Tz = "Europe/London".parse().unwrap();
        // Thursday 19 Nov 2026 → Sunday 22 Nov 23:59:59 GMT.
        assert_eq!(end_of_weekend(t("2026-11-19T12:00:00Z"), london), t("2026-11-22T23:59:59Z"));
        // On Sunday itself it is the same day.
        assert_eq!(end_of_weekend(t("2026-11-22T08:00:00Z"), london), t("2026-11-22T23:59:59Z"));
    }

    #[test]
    fn weekend_lists_exact_and_day_dates_but_not_placeholders() {
        use crate::state::{Bar, Launch};
        let launch = |id: u32, t0: &str, precision: Precision| Launch {
            id,
            name: format!("L{id}"),
            provider: String::new(),
            rocket: String::new(),
            pad: String::new(),
            location: String::new(),
            t0: t0.into(),
            precision,
            net: if precision == Precision::Exact { String::new() } else { format!("NET L{id}") },
            status: String::new(),
            status_id: 0,
            status_color: String::new(),
            pinned: false,
        };
        let state = State {
            schema_version: 1,
            generated_at: String::new(),
            sources: Default::default(),
            campaign: None,
            launches: vec![
                launch(1, "2026-11-21T20:30:00Z", Precision::Exact),
                // Sunday, time TBD: its 23:59:59Z placeholder is already Monday in Berlin.
                launch(2, "2026-11-22T23:59:59Z", Precision::Day),
                // A coarse placeholder that happens to fall on this Sunday.
                launch(3, "2026-11-22T23:59:59Z", Precision::Quarter),
                launch(4, "2026-11-21T04:30:00Z", Precision::Exact),
            ],
            next: None,
            bar: Bar { label: String::new(), t0: None, net: String::new(), progress: String::new(), stale_after: None },
        };
        let berlin: Tz = "Europe/Berlin".parse().unwrap();
        let slate = weekend(&state, &[berlin], t("2026-11-19T12:00:00Z"));
        assert!(slate.contains("Sat 21 Nov 21:30 CET / 20:30 UTC"), "{slate}");
        assert!(slate.contains("L2") && !slate.contains("L3"), "{slate}");
        // Friday evening in Los Angeles is already Saturday in UTC.
        let la: Tz = "America/Los_Angeles".parse().unwrap();
        let slate = weekend(&state, &[la], t("2026-11-19T12:00:00Z"));
        assert!(slate.contains("Fri 20 Nov 20:30 PST / Sat 04:30 UTC"), "{slate}");
    }
}
