//! Files under `~/.local/share/flightdeck/` and the rules for writing them.
//!
//! One writer at a time: whoever holds `writer.lock` (the daemon, or a one-shot
//! CLI command when no daemon runs) owns `cache.json`, `state.json` and
//! `alerts.json`. `overrides.json` is the user's intent; only CLI commands write
//! it, under its own lock, and the writer picks changes up by mtime.

use anyhow::{Context, Result};
use fs2::FileExt;
use serde::{de::DeserializeOwned, Serialize};
use std::fs::{self, DirBuilder, File, OpenOptions};
use std::io::Write;
#[cfg(unix)]
use std::os::unix::fs::{DirBuilderExt, OpenOptionsExt};
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

fn ensure_private_dir(dir: &Path) -> Result<()> {
    let mut b = DirBuilder::new();
    b.recursive(true);
    #[cfg(unix)]
    b.mode(0o700);
    b.create(dir).with_context(|| format!("creating {}", dir.display()))
}

/// Writes raw bytes to an exclusive, random-named temp file (`O_CREAT | O_EXCL`,
/// `0600`) in the target directory and atomically renames over `path`, so a
/// pre-placed symlink at a temp path or at `path` itself is never followed.
pub fn write_bytes_atomic(path: &Path, bytes: &[u8]) -> Result<()> {
    let dir = path.parent().context("path has no parent")?;
    ensure_private_dir(dir)?;
    let mut tmp = tempfile::Builder::new()
        .prefix(".flightdeck-")
        .suffix(".tmp")
        .tempfile_in(dir)
        .with_context(|| format!("creating temp file in {}", dir.display()))?;
    tmp.write_all(bytes)?;
    tmp.as_file().sync_all()?;
    tmp.persist(path)
        .map_err(|e| e.error)
        .with_context(|| format!("replacing {}", path.display()))?;
    Ok(())
}

/// Writes beside the target using an exclusive temp file and renames over it,
/// so readers never see a torn file and symlinks are never followed.
pub fn write_json_atomic<T: Serialize>(path: &Path, value: &T) -> Result<()> {
    let dir = path.parent().context("path has no parent")?;
    ensure_private_dir(dir)?;
    let mut tmp = tempfile::Builder::new()
        .prefix(".flightdeck-")
        .suffix(".tmp")
        .tempfile_in(dir)
        .with_context(|| format!("creating temp file in {}", dir.display()))?;
    {
        let mut w = std::io::BufWriter::new(tmp.as_file_mut());
        serde_json::to_writer(&mut w, value)?;
        w.write_all(b"\n")?;
        w.flush()?;
    }
    tmp.as_file().sync_all()?;
    tmp.persist(path)
        .map_err(|e| e.error)
        .with_context(|| format!("replacing {}", path.display()))?;
    Ok(())
}

/// The file's mtime and inode; `None` when it is missing or can't be read.
pub fn identity(path: &Path) -> Option<(SystemTime, u64)> {
    use std::os::unix::fs::MetadataExt;
    fs::metadata(path).ok().and_then(|m| Some((m.modified().ok()?, m.ino())))
}

/// Holds an exclusive `flock` until dropped.
pub struct Lock(#[allow(dead_code)] File);

fn open_lock(path: &Path) -> Result<File> {
    let dir = path.parent().context("lock path has no parent")?;
    ensure_private_dir(dir)?;
    let mut opts = OpenOptions::new();
    opts.create(true).truncate(false).write(true);
    #[cfg(unix)]
    opts.mode(0o600).custom_flags(libc::O_NOFOLLOW);
    opts.open(path).with_context(|| format!("opening {}", path.display()))
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

    #[cfg(unix)]
    #[test]
    fn atomic_write_and_locks_do_not_follow_symlinks() {
        use std::os::unix::fs::symlink;

        let outside = tempfile::tempdir().unwrap();
        let sentinel = outside.path().join("sentinel.txt");
        fs::write(&sentinel, b"untouched").unwrap();

        let dir = tempfile::tempdir().unwrap();
        let target = dir.path().join("state.json");
        let predictable_tmp = dir.path().join(format!(".state.json.{}.tmp", std::process::id()));
        symlink(&sentinel, &predictable_tmp).unwrap();
        symlink(&sentinel, &target).unwrap();

        write_json_atomic(&target, &serde_json::json!({"ok": true})).unwrap();
        assert_eq!(fs::read(&sentinel).unwrap(), b"untouched");
        assert!(!fs::symlink_metadata(&target).unwrap().file_type().is_symlink());
        assert_eq!(read_json::<serde_json::Value>(&target).unwrap(), serde_json::json!({"ok": true}));

        let lock_path = dir.path().join("writer.lock");
        symlink(&sentinel, &lock_path).unwrap();
        assert!(Lock::try_writer(&Paths::new(dir.path().to_path_buf())).is_err());
        assert_eq!(fs::read(&sentinel).unwrap(), b"untouched");
    }
}
