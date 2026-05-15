// Canon  - A Societal Kernel
// Copyright (C) 2026  Adam Hall
// This program comes with ABSOLUTELY NO WARRANTY.
// This is free software, and you are welcome to redistribute it
// under certain conditions. See: https://github.com/hatter6822/Orbcrypt/blob/main/LICENSE

//! `canon-indexer` — RH-E.1 skeleton entry-point.
//!
//! The implementing work unit (`docs/planning/rust_host_runtime_plan.md`
//! §RH-E.1) replaces this `main` with the `SQLite` indexer that
//! subscribes to events via `canon-event-subscribe`, maintains a
//! per-(actor, resource) balance view in `canon-storage`, and
//! supports `canon-indexer query` for ad-hoc lookups.

// `canon-storage` is declared as a dependency in `Cargo.toml` so the
// dependency graph is locked in at the workspace-skeleton stage;
// the skeleton main does not yet use any of its public items.
use canon_cli_common::exit::OperatorExitCode;
use canon_storage as _;

fn main() {
    eprintln!(
        "canon-indexer: RH-E.1 not yet implemented; see docs/planning/rust_host_runtime_plan.md §RH-E.1"
    );
    OperatorExitCode::NotImplemented.terminate();
}
