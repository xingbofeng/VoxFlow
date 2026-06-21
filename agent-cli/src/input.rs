use anyhow::{Context, Result};
use std::ffi::CString;
use std::fs::OpenOptions;
use std::io::{Read, Write};
use std::os::unix::ffi::OsStrExt;
use std::os::unix::fs::{OpenOptionsExt, PermissionsExt};
use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex};
use std::time::Duration;

pub type SharedWriter = Arc<Mutex<Box<dyn Write + Send>>>;

const SUBMIT_KEY_DELAY: Duration = Duration::from_millis(35);

pub struct InputChannel {
    path: PathBuf,
}

impl InputChannel {
    pub fn create(path: impl AsRef<Path>) -> Result<Self> {
        let path = path.as_ref().to_owned();
        if let Some(parent) = path.parent() {
            std::fs::create_dir_all(parent)?;
            std::fs::set_permissions(parent, std::fs::Permissions::from_mode(0o700))?;
        }
        let _ = std::fs::remove_file(&path);
        let c_path = CString::new(path.as_os_str().as_bytes())?;
        if unsafe { libc::mkfifo(c_path.as_ptr(), 0o600) } != 0 {
            return Err(std::io::Error::last_os_error()).context("create VoxFlow input FIFO");
        }
        Ok(Self { path })
    }

    pub fn path(&self) -> &Path {
        &self.path
    }

    pub fn start_forwarding(&self, writer: SharedWriter) -> Result<std::thread::JoinHandle<()>> {
        // O_RDWR mirrors agent-yes: the FIFO remains readable between short-lived send clients.
        let mut input = OpenOptions::new().read(true).write(true).open(&self.path)?;
        Ok(std::thread::spawn(move || {
            let mut buffer = [0_u8; 8192];
            loop {
                match input.read(&mut buffer) {
                    Ok(0) => std::thread::sleep(std::time::Duration::from_millis(25)),
                    Ok(length) => {
                        let Ok(mut target) = writer.lock() else {
                            break;
                        };
                        if target
                            .write_all(&buffer[..length])
                            .and_then(|_| target.flush())
                            .is_err()
                        {
                            break;
                        }
                    }
                    Err(error) if error.kind() == std::io::ErrorKind::Interrupted => continue,
                    Err(_) => break,
                }
            }
        }))
    }

    pub fn send(path: impl AsRef<Path>, message: &str, submit: bool) -> Result<()> {
        let mut output = OpenOptions::new()
            .write(true)
            .mode(0o600)
            .open(path.as_ref())?;
        output.write_all(message.as_bytes())?;
        if submit {
            output.flush()?;
            std::thread::sleep(SUBMIT_KEY_DELAY);
            output.write_all(b"\r")?;
        }
        output.flush()?;
        Ok(())
    }
}

impl Drop for InputChannel {
    fn drop(&mut self) {
        let _ = std::fs::remove_file(&self.path);
    }
}
