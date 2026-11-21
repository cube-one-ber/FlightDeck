//! Client for the Next Spaceflight API (`api.nextspaceflight.com/api/`).
//!
//! The API is public but undocumented, recovered from the Android app. Every
//! field is optional and unknown fields are ignored, so a schema change degrades
//! to missing data instead of a failed sync.

use crate::config::Config;
use anyhow::{bail, Context, Result};
use serde::{de::DeserializeOwned, Deserialize, Serialize};
use std::io::Read;
use std::time::Duration;

/// Hard cap on any single API response body so a runaway or hostile response
/// cannot exhaust memory before JSON decoding.
const MAX_RESPONSE_BYTES: u64 = 16 * 1024 * 1024;

fn read_bounded<R: Read>(reader: R, limit: u64, label: &str) -> Result<Vec<u8>> {
    let mut buf = Vec::new();
    let read = reader
        .take(limit.saturating_add(1))
        .read_to_end(&mut buf)
        .with_context(|| format!("reading {label}"))?;
    if read as u64 > limit {
        bail!("GET {label}: response exceeded {limit} bytes");
    }
    Ok(buf)
}

/// Removes `null` object fields, so `#[serde(default)]` covers a field the API
/// sends as null just as it covers one it leaves out.
fn drop_nulls(v: &mut serde_json::Value) {
    match v {
        serde_json::Value::Object(map) => {
            map.retain(|_, x| !x.is_null());
            map.values_mut().for_each(drop_nulls);
        }
        serde_json::Value::Array(items) => items.iter_mut().for_each(drop_nulls),
        _ => {}
    }
}

pub struct Client {
    http: reqwest::blocking::Client,
    base: String,
}

impl Client {
    pub fn new(cfg: &Config) -> Result<Self> {
        let http = reqwest::blocking::Client::builder()
            .user_agent(concat!("flightdeck/", env!("CARGO_PKG_VERSION")))
            .timeout(Duration::from_secs(20))
            .build()?;
        Ok(Self { http, base: cfg.base_url.clone() })
    }

    fn get<T: DeserializeOwned>(&self, path: &str) -> Result<T> {
        let resp = self
            .http
            .get(format!("{}{}", self.base, path))
            .send()
            .with_context(|| format!("GET {path}"))?;
        let status = resp.status();
        if !status.is_success() {
            bail!("GET {path}: HTTP {status}");
        }
        if resp.content_length().is_some_and(|n| n > MAX_RESPONSE_BYTES) {
            bail!("GET {path}: response exceeded {MAX_RESPONSE_BYTES} bytes");
        }
        let body = read_bounded(resp, MAX_RESPONSE_BYTES, path)?;
        let mut value: serde_json::Value = serde_json::from_slice(&body).with_context(|| format!("decoding {path}"))?;
        drop_nulls(&mut value);
        serde_json::from_value(value).with_context(|| format!("decoding {path}"))
    }

    pub fn starship(&self) -> Result<StarshipData> {
        self.get("starship_data/")
    }

    pub fn launches(&self) -> Result<Vec<LaunchRow>> {
        Ok(self.get::<Listing<LaunchRow>>("launches/")?.list)
    }

    pub fn lookups(&self) -> Result<Lookups> {
        Ok(Lookups {
            statuses: self.get::<Listing<LaunchStatus>>("statuses/")?.list,
            configs: self.get::<Listing<RocketConfig>>("configs/")?.list,
            agencies: self.get::<Listing<Agency>>("agencies/")?.list,
            pads: self.get::<Listing<Pad>>("pads/")?.list,
        })
    }
}

#[derive(Deserialize)]
struct Listing<T> {
    #[serde(default = "Vec::new")]
    list: Vec<T>,
}

#[derive(Debug, Clone, Default, Deserialize, Serialize, PartialEq)]
#[serde(default)]
pub struct StarshipData {
    pub status_manager: Option<StatusManager>,
    pub statuses: Vec<RemoteMilestone>,
    pub vehicles: Vec<Vehicle>,
    pub tests: Vec<VehicleTest>,
    /// Shape unknown (empty whenever observed); passed through as-is.
    pub closures: Vec<serde_json::Value>,
    pub tfrs: Vec<serde_json::Value>,
    pub weather: Option<Weather>,
    pub videos: Vec<Video>,
}

#[derive(Debug, Clone, Default, Deserialize, Serialize, PartialEq)]
#[serde(default)]
pub struct StatusManager {
    pub id: u32,
    pub title: String,
    pub starbase_live: Option<String>,
}

#[derive(Debug, Clone, Default, Deserialize, Serialize, PartialEq)]
#[serde(default)]
pub struct RemoteMilestone {
    pub id: u32,
    pub title: String,
    pub confirmed: bool,
    pub url: Option<String>,
}

#[derive(Debug, Clone, Default, Deserialize, Serialize, PartialEq)]
#[serde(default)]
pub struct Vehicle {
    pub id: u32,
    pub name: String,
    #[serde(rename = "type")]
    pub kind: String,
    pub status: String,
    pub ordering: f64,
    pub notes: Option<String>,
}

#[derive(Debug, Clone, Default, Deserialize, Serialize, PartialEq)]
#[serde(default)]
pub struct VehicleTest {
    pub id: u32,
    pub name: String,
    pub date: Option<String>,
    pub location: Option<String>,
    pub vid_url: Option<String>,
}

#[derive(Debug, Clone, Default, Deserialize, Serialize, PartialEq)]
#[serde(default)]
pub struct Weather {
    pub location: String,
    pub weather: String,
    /// Kelvin, as the API sends it.
    pub temp: Option<f64>,
    /// Metres per second.
    pub wind: Option<f64>,
    pub gusts: Option<f64>,
}

#[derive(Debug, Clone, Default, Deserialize, Serialize, PartialEq)]
#[serde(default)]
pub struct Video {
    pub id: u64,
    pub title: String,
    pub date: Option<String>,
    pub url: Option<String>,
}

/// One row of the compact `launches/` list.
#[derive(Debug, Clone, Default, Deserialize, Serialize, PartialEq)]
#[serde(default)]
pub struct LaunchRow {
    #[serde(rename = "i")]
    pub id: u32,
    #[serde(rename = "n")]
    pub name: String,
    #[serde(rename = "l")]
    pub agency: Option<u32>,
    #[serde(rename = "s")]
    pub status: u32,
    #[serde(rename = "t")]
    pub t0: Option<String>,
    #[serde(rename = "r")]
    pub config: Option<u32>,
    #[serde(rename = "p")]
    pub pad: Option<u32>,
}

#[derive(Debug, Clone, Default, Deserialize, Serialize, PartialEq)]
pub struct Lookups {
    pub statuses: Vec<LaunchStatus>,
    pub configs: Vec<RocketConfig>,
    pub agencies: Vec<Agency>,
    pub pads: Vec<Pad>,
}

#[derive(Debug, Clone, Default, Deserialize, Serialize, PartialEq)]
#[serde(default)]
pub struct LaunchStatus {
    pub id: u32,
    pub name: String,
    pub color: String,
}

#[derive(Debug, Clone, Default, Deserialize, Serialize, PartialEq)]
#[serde(default)]
pub struct RocketConfig {
    pub id: u32,
    pub name: String,
}

#[derive(Debug, Clone, Default, Deserialize, Serialize, PartialEq)]
#[serde(default)]
pub struct Agency {
    pub id: u32,
    pub name: String,
    pub abbrev: String,
}

#[derive(Debug, Clone, Default, Deserialize, Serialize, PartialEq)]
#[serde(default)]
pub struct Pad {
    pub id: u32,
    pub name: String,
    pub location_name: String,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn tolerates_missing_and_unknown_fields() {
        let data: StarshipData = serde_json::from_str(
            r#"{"statuses":[{"id":1,"title":"Stacked","new_field":3}],"weather":null,"surprise":[]}"#,
        )
        .unwrap();
        assert_eq!(data.statuses[0].title, "Stacked");
        assert!(!data.statuses[0].confirmed);
        assert!(data.status_manager.is_none());

        let row: LaunchRow = serde_json::from_str(r#"{"i":7,"n":"X","s":2,"t":null}"#).unwrap();
        assert_eq!((row.id, row.status, row.t0), (7, 2, None));
    }

    #[test]
    fn explicit_nulls_fall_back_to_defaults() {
        let mut v = serde_json::json!({"list":[{"i":7,"n":null,"s":null,"p":null}]});
        drop_nulls(&mut v);
        let rows = serde_json::from_value::<Listing<LaunchRow>>(v).unwrap().list;
        assert_eq!((rows[0].id, rows[0].name.as_str(), rows[0].status, rows[0].pad), (7, "", 0, None));
    }

    #[test]
    fn rejects_oversized_responses() {
        let ok = read_bounded(&b"hello"[..], 5, "test").unwrap();
        assert_eq!(ok, b"hello");
        assert!(read_bounded(&b"hello!"[..], 5, "test").is_err());
    }
}
