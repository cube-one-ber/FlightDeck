//! Files under `~/.local/share/flightdeck/` and the rules for writing them.
//!
//! One writer at a time: whoever holds `writer.lock` (the daemon, or a one-shot
//! CLI command when no daemon runs) owns `cache.json`, `state.json` and
//! `alerts.json`. `overrides.json` is the user's intent; only CLI commands write
//! it, under its own lock, and the writer picks changes up by mtime.

use anyhow::{Context, Result};
use fs2::FileExt;
use serde::{de::DeserializeOwned, Serialize};
use std::fs::{self, File, OpenOptions};
use std::io::Write;
use std::path::{Path, PathBuf};
use std::time::SystemTime;

#[derive(Debug, Clone)]
pub struct Paths {
    pub dir: PathBuf,
}

impl Paths {
    pub fn new(dir: PathBuf) -> Self {
        Self { dir }
    }

    /// `$XDG_DATA_HOME/flightdeck`, usually `~/.local/share/flightdeck`.
    pub fn default_dir() -> PathBuf {
        std::env::var_os("XDG_DATA_HOME")
            .filter(|d| !d.is_empty())
            .map(PathBuf::from)
            .unwrap_or_else(|| crate::config::home().join(".local/share"))
            .join("flightdeck")
    }

    pub fn state(&self) -> PathBuf {
        self.dir.join("state.json")
    }
    pub fn cache(&self) -> PathBuf {
        self.dir.join("cache.json")
    }
    pub fn overrides(&self) -> PathBuf {
        self.dir.join("overrides.json")
    }
    pub fn alerts(&self) -> PathBuf {
        self.dir.join("alerts.json")
    }
    /// Touched by `flightdeck sync` to ask a running daemon to poll now.
    pub fn refresh(&self) -> PathBuf {
        self.dir.join("refresh")
    }
}

/// Reads JSON, treating a missing file as the default value.
pub fn read_json<T: DeserializeOwned + Default>(path: &Path) -> Result<T> {
    match fs::read(path) {
        Ok(bytes) => serde_json::from_slice(&bytes).with_context(|| format!("parsing {}", path.display())),
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(T::default()),
        Err(e) => Err(e).with_context(|| format!("reading {}", path.display())),
    }
}

/// Writes beside the target and renames over it, so readers never see a torn file.
pub fn write_json_atomic<T: Serialize>(path: &Path, value: &T) -> Result<()> {
    let dir = path.parent().context("path has no parent")?;
    fs::create_dir_all(dir)?;
    let tmp = dir.join(format!(".{}.{}.tmp", path.file_name().unwrap().to_string_lossy(), std::process::id()));
    {
        let mut f = std::io::BufWriter::new(File::create(&tmp)?);
        serde_json::to_writer(&mut f, value)?;
        f.write_all(b"\n")?;
        f.into_inner().map_err(|e| e.into_error())?.sync_all()?;
    }
    fs::rename(&tmp, path).with_context(|| format!("replacing {}", path.display()))
}

/// The file's mtime and inode; `None` when it is missing or can't be read.
pub fn identity(path: &Path) -> Option<(SystemTime, u64)> {
    use std::os::unix::fs::MetadataExt;
    fs::metadata(path).ok().and_then(|m| Some((m.modified().ok()?, m.ino())))
}

/// Holds an exclusive `flock` until dropped.
pub struct Lock(#[allow(dead_code)] File);

fn open_lock(path: &Path) -> Result<File> {
    fs::create_dir_all(path.parent().unwrap())?;
    Ok(OpenOptions::new().create(true).truncate(false).write(true).open(path)?)
}

impl Lock {
    /// The writer lock, or `None` when another process (normally the daemon) has it.
    pub fn try_writer(paths: &Paths) -> Result<Option<Lock>> {
        let f = open_lock(&paths.dir.join("writer.lock"))?;
        match f.try_lock_exclusive() {
            Ok(()) => Ok(Some(Lock(f))),
            Err(e) if e.kind() == fs2::lock_contended_error().kind() => Ok(None),
            Err(e) => Err(e).context("locking writer.lock"),
        }
    }

    /// The writer lock, waiting for a one-shot command to finish with it.
    pub fn writer(paths: &Paths) -> Result<Lock> {
        let f = open_lock(&paths.dir.join("writer.lock"))?;
        f.lock_exclusive().context("locking writer.lock")?;
        Ok(Lock(f))
    }

    /// Serialises read-modify-write of `overrides.json` between CLI calls.
    pub fn overrides(paths: &Paths) -> Result<Lock> {
        let f = open_lock(&paths.dir.join("overrides.lock"))?;
        f.lock_exclusive()?;
        Ok(Lock(f))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn writer_lock_is_exclusive_and_released_on_drop() {
        let dir = tempfile::tempdir().unwrap();
        let paths = Paths::new(dir.path().to_path_buf());
        let held = Lock::try_writer(&paths).unwrap();
        assert!(held.is_some());
        assert!(Lock::try_writer(&paths).unwrap().is_none());
        drop(held);
        assert!(Lock::try_writer(&paths).unwrap().is_some());
    }
}
