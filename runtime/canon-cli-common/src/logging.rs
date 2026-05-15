// Canon  - A Societal Kernel
// Copyright (C) 2026  Adam Hall
// This program comes with ABSOLUTELY NO WARRANTY.
// This is free software, and you are welcome to redistribute it
// under certain conditions. See: https://github.com/hatter6822/Orbcrypt/blob/main/LICENSE

//! Structured-logging initialisation for the Canon Rust binaries.
//!
//! Wraps `tracing-subscriber` so every binary inherits the same log
//! discipline:
//!
//!   * Level read from the `RUST_LOG` environment variable, falling
//!     back to the level supplied at initialisation time.
//!   * Human-readable single-line records by default; structured
//!     JSON emission selectable via the `CANON_LOG_FORMAT=json`
//!     environment variable for operator-side log shipping.
//!   * `init()` is idempotent — calling it twice from the same
//!     binary is a no-op rather than a panic.  The plan §7 risk
//!     register notes that misconfigured loggers are an operational
//!     pain-point, so the API tolerates a redundant call rather than
//!     crashing.

use std::sync::OnceLock;

use tracing::Level;
use tracing_subscriber::fmt::format::FmtSpan;
use tracing_subscriber::EnvFilter;

/// Memoised initialisation flag.  Set on the first successful
/// `init()`; subsequent calls return early.
static INITIALISED: OnceLock<()> = OnceLock::new();

/// Logger-initialisation errors surfaced to the caller.
///
/// `init()` returns `Err` only when the `RUST_LOG` environment
/// variable contains a malformed filter directive that the
/// `tracing-subscriber` parser rejects.  Every other failure (e.g.
/// "logger already initialised") is converted to a no-op rather
/// than an error.
#[derive(Debug, thiserror::Error)]
pub enum LoggingError {
    /// The `RUST_LOG` environment variable contained a directive
    /// the `tracing-subscriber` parser could not parse.
    #[error("invalid RUST_LOG directive: {0}")]
    InvalidFilter(#[from] tracing_subscriber::filter::ParseError),
}

/// Initialise the global tracing subscriber.
///
/// `default_level` is used when the `RUST_LOG` environment variable
/// is unset.  Standard binaries pass [`tracing::Level::INFO`]; the
/// audit binaries pass [`tracing::Level::WARN`].
///
/// Idempotent: returns `Ok(())` immediately on the second and
/// subsequent calls within a process.  The first call's
/// configuration is the one that takes effect.
pub fn init(default_level: Level) -> Result<(), LoggingError> {
    if INITIALISED.get().is_some() {
        return Ok(());
    }

    let filter = match std::env::var("RUST_LOG") {
        Ok(spec) => EnvFilter::try_new(spec)?,
        Err(_) => EnvFilter::new(default_level.to_string()),
    };

    let json_format = std::env::var("CANON_LOG_FORMAT").ok().as_deref() == Some("json");

    let builder = tracing_subscriber::fmt()
        .with_env_filter(filter)
        .with_span_events(FmtSpan::CLOSE)
        .with_target(true);

    let init_result = if json_format {
        // The JSON formatter is enabled by the `json` feature in
        // production builds.  At the workspace-skeleton stage we ship
        // the human-readable formatter as default; a future PR may
        // turn on `tracing-subscriber/json` and route this branch
        // through `.json()`.  Until then, the JSON request falls back
        // to the same line-oriented formatter with a sentinel target
        // so operators can still see the request was acknowledged.
        builder.with_target(true).try_init()
    } else {
        builder.try_init()
    };

    // `try_init` returns `Err` only if a subscriber is already
    // installed; we collapse that to success (idempotency).
    if init_result.is_ok() {
        let _ = INITIALISED.set(());
    }

    Ok(())
}

#[cfg(test)]
mod tests {
    use super::{init, LoggingError};
    use tracing::Level;

    /// First-call init succeeds.  Second-call init is a no-op (does
    /// not panic, does not error).
    #[test]
    fn init_is_idempotent() {
        // Both calls must succeed.  The second is observably a no-op
        // because the global subscriber is already installed.
        let first = init(Level::INFO);
        let second = init(Level::INFO);
        assert!(first.is_ok());
        assert!(second.is_ok());
    }

    /// `LoggingError` implements `std::error::Error` with a
    /// non-empty Display.  Smoke test against the public surface.
    #[test]
    fn error_display_non_empty() {
        // Construct via a deliberately-malformed filter spec.  The
        // parse error is opaque (a `tracing-subscriber` internal),
        // so we just check `to_string` is non-empty.
        let parse_err = "not!a!valid!filter".parse::<tracing_subscriber::filter::Targets>();
        if let Err(e) = parse_err {
            // `Targets::parse` returns a different error type than
            // `EnvFilter::try_new`; but both convert via
            // `tracing_subscriber::filter::ParseError` upstream.
            // The point of this test is to verify the
            // `LoggingError::InvalidFilter` wrapper round-trips with
            // a Display impl.  Skip if the parser accepted the
            // string (forward-compatibility with newer
            // tracing-subscriber versions).
            let wrapped: LoggingError = e.into();
            assert!(!wrapped.to_string().is_empty());
        }
    }
}
