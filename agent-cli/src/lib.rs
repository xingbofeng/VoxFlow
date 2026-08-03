#![recursion_limit = "256"]

#[cfg(feature = "builtin-agent")]
pub mod builtin_agent;
// The full `voxflow` command is intentionally Unix-only.  Keep these modules
// out of the Windows dependency graph so the shipped `voxflow-agent` sidecar
// cannot accidentally pull in Router, PTY, MCP, or Unix socket support.
#[cfg(all(feature = "full-cli", unix))]
pub mod cli;
#[cfg(all(feature = "full-cli", unix))]
pub mod input;
#[cfg(all(feature = "full-cli", unix))]
pub mod ipc;
#[cfg(all(feature = "full-cli", unix))]
pub mod mcp;
#[cfg(all(feature = "full-cli", unix))]
pub mod mcp_config;
#[cfg(all(feature = "full-cli", unix))]
pub mod paths;
#[cfg(all(feature = "full-cli", unix))]
pub mod pty;
#[cfg(all(feature = "full-cli", unix))]
pub mod router;
#[cfg(all(feature = "full-cli", unix))]
pub mod session;
#[cfg(all(feature = "full-cli", unix))]
pub mod wrapper;
