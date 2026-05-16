// Canon  - A Societal Kernel
// Copyright (C) 2026  Adam Hall
// This program comes with ABSOLUTELY NO WARRANTY.
// This is free software, and you are welcome to redistribute it
// under certain conditions. See: https://github.com/hatter6822/Orbcrypt/blob/main/LICENSE

//! Persistent watcher state.
//!
//! ## What's persisted
//!
//! Two pieces of state survive across restarts:
//!
//!   1. **Last confirmed block** — the highest block number whose
//!      events have been forwarded to `canon-host`.  On startup
//!      the watcher resumes from this block + 1.
//!   2. **Forwarded-event ledger** — the set of `(block_hash,
//!      tx_hash, log_index)` triples that have already been
//!      forwarded.  Used for idempotency: a duplicate event
//!      arriving (e.g. from a shallow re-org that puts an event
//!      back at a different block) is silently dropped.
//!
//! Also persisted, but in memory only between restarts:
//!
//!   3. **AddressBook** — the `EthAddress → ActorId` mapping
//!      maintained by `translation::ingest`.  Persisted to disk
//!      so the daemon resumes with the same `next_actor_id`.
//!
//! ## On-disk format
//!
//! JSONL (one JSON object per line) is the chosen format:
//!
//!   * Append-only writes (durable on each event).
//!   * Human-inspectable.
//!   * No DB dependency until RH-E.0 lands.
//!
//! Each line is one [`StateRecord`]:
//!
//! ```jsonc
//! {"event": "forwarded", "block_hash": "0x...", "tx_hash": "0x...", "log_index": N}
//! {"event": "confirmed", "block_number": N}
//! {"event": "address_assigned", "address": "0x...", "actor_id": N}
//! ```
//!
//! Rebuilding state on startup walks the file and replays each
//! record into in-memory data structures.  Compaction (when the
//! file grows large) is out of scope for the RH-B landing; the
//! planned RH-E.0 SQLite layer will replace this entirely.

use std::collections::{BTreeMap, HashSet};
use std::fs::{File, OpenOptions};
use std::io::{BufRead, BufReader, BufWriter, Write};
use std::path::{Path, PathBuf};

use serde::{Deserialize, Serialize};

use crate::action::{ActorId, EthAddress};
use crate::address_book::AddressBook;
use crate::events::TopicHash;

/// Errors surfaced by the persistent state layer.
#[derive(Debug, thiserror::Error)]
pub enum StateError {
    /// An I/O error from the underlying filesystem.
    #[error("state I/O error at {path}: {source}")]
    Io {
        /// The path that errored.
        path: PathBuf,
        /// The underlying I/O error.
        #[source]
        source: std::io::Error,
    },
    /// A line in the state file could not be parsed as JSON or
    /// the JSON did not match the expected schema.
    #[error("malformed state record at line {line_number}: {message}")]
    Malformed {
        /// Line number (1-indexed) of the offending record.
        line_number: usize,
        /// Diagnostic message.
        message: String,
    },
}

/// One record in the on-disk state file.  Tagged enum so the
/// JSON form has a discriminating `event` field.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
#[serde(tag = "event")]
pub enum StateRecord {
    /// An event was forwarded to `canon-host`.  Identified by
    /// the `(block_hash, tx_hash, log_index)` triple.
    #[serde(rename = "forwarded")]
    Forwarded {
        /// The L1 block hash the event was originally observed
        /// in.  Used for re-org-tolerant dedup keying.
        block_hash: HexBytes,
        /// The L1 transaction hash.
        tx_hash: HexBytes,
        /// The log index within the transaction.
        log_index: u64,
    },
    /// Confirmed-progress marker.  Records the highest block
    /// number whose events have all been processed.
    #[serde(rename = "confirmed")]
    Confirmed {
        /// The block number.
        block_number: u64,
    },
    /// Address-book assignment record.  Records that
    /// `address` was assigned `actor_id`.
    #[serde(rename = "address_assigned")]
    AddressAssigned {
        /// The Ethereum address.
        address: HexBytes,
        /// The assigned `ActorId`.
        actor_id: ActorId,
    },
}

/// Hex-encoded byte buffer.  Used in `StateRecord` to make the
/// on-disk JSON human-readable.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct HexBytes(pub Vec<u8>);

impl Serialize for HexBytes {
    fn serialize<S: serde::Serializer>(&self, serializer: S) -> Result<S::Ok, S::Error> {
        let mut s = String::with_capacity(2 + self.0.len() * 2);
        s.push_str("0x");
        for b in &self.0 {
            s.push(hex_char(b >> 4));
            s.push(hex_char(b & 0x0f));
        }
        serializer.serialize_str(&s)
    }
}

impl<'de> Deserialize<'de> for HexBytes {
    fn deserialize<D: serde::Deserializer<'de>>(deserializer: D) -> Result<Self, D::Error> {
        let s = String::deserialize(deserializer)?;
        let stripped = s
            .strip_prefix("0x")
            .ok_or_else(|| serde::de::Error::custom("expected 0x-prefixed hex string"))?;
        if stripped.len() % 2 != 0 {
            return Err(serde::de::Error::custom("hex string has odd length"));
        }
        let mut out = Vec::with_capacity(stripped.len() / 2);
        for chunk in stripped.as_bytes().chunks(2) {
            let hi = hex_value(chunk[0]).ok_or_else(|| {
                serde::de::Error::custom(format!("invalid hex char: {}", chunk[0] as char))
            })?;
            let lo = hex_value(chunk[1]).ok_or_else(|| {
                serde::de::Error::custom(format!("invalid hex char: {}", chunk[1] as char))
            })?;
            out.push((hi << 4) | lo);
        }
        Ok(Self(out))
    }
}

/// Map nibble (0..=15) to ASCII hex character.
fn hex_char(n: u8) -> char {
    match n {
        0..=9 => (b'0' + n) as char,
        10..=15 => (b'a' + (n - 10)) as char,
        _ => '?',
    }
}

/// Map ASCII hex character to nibble.
fn hex_value(c: u8) -> Option<u8> {
    match c {
        b'0'..=b'9' => Some(c - b'0'),
        b'a'..=b'f' => Some(10 + c - b'a'),
        b'A'..=b'F' => Some(10 + c - b'A'),
        _ => None,
    }
}

/// The reconstructed in-memory state from a state file.
#[derive(Clone, Debug)]
pub struct WatcherState {
    /// Block number up to and including which the watcher has
    /// processed all events.  Resumed-from on startup.
    pub last_confirmed_block: Option<u64>,
    /// Set of `(block_hash, tx_hash, log_index)` triples already
    /// forwarded.  Used for idempotency.
    pub forwarded: HashSet<ForwardedKey>,
    /// The reconstructed `AddressBook`.
    pub address_book: AddressBook,
}

impl Default for WatcherState {
    fn default() -> Self {
        Self {
            last_confirmed_block: None,
            forwarded: HashSet::new(),
            address_book: AddressBook::new(),
        }
    }
}

/// Key in the forwarded-events set.
#[derive(Clone, Debug, Eq, PartialEq, Hash)]
pub struct ForwardedKey {
    /// The L1 block hash.
    pub block_hash: TopicHash,
    /// The L1 transaction hash.
    pub tx_hash: TopicHash,
    /// The log index.
    pub log_index: u64,
}

/// Persistent watcher-state store.
///
/// The store is append-only — every state change writes one new
/// JSONL record.  On startup, [`Self::load`] walks the file and
/// rebuilds the in-memory state.
///
/// ## Thread-safety
///
/// `StateStore` is **not** `Sync`-shared.  The watcher loop is
/// single-threaded by design: every state mutation happens on
/// the same thread that holds the `&mut StateStore`.  Re-orgs do
/// not preempt the mutation thread.
#[derive(Debug)]
pub struct StateStore {
    path: PathBuf,
    writer: BufWriter<File>,
}

impl StateStore {
    /// Open or create the state file at `path`, replay every
    /// record, and return the reconstructed [`WatcherState`]
    /// alongside the open store.
    ///
    /// On a missing file, returns an empty `WatcherState`.
    ///
    /// # Errors
    ///
    /// Returns `StateError::Io` on filesystem errors and
    /// `StateError::Malformed` on a corrupted record.
    pub fn open(path: &Path) -> Result<(Self, WatcherState), StateError> {
        let state = if path.exists() {
            Self::replay(path)?
        } else {
            WatcherState::default()
        };
        let file = OpenOptions::new()
            .create(true)
            .append(true)
            .open(path)
            .map_err(|source| StateError::Io {
                path: path.to_path_buf(),
                source,
            })?;
        Ok((
            Self {
                path: path.to_path_buf(),
                writer: BufWriter::new(file),
            },
            state,
        ))
    }

    /// Walk the file and rebuild the in-memory state.
    fn replay(path: &Path) -> Result<WatcherState, StateError> {
        let file = File::open(path).map_err(|source| StateError::Io {
            path: path.to_path_buf(),
            source,
        })?;
        let reader = BufReader::new(file);
        let mut state = WatcherState::default();
        // For replay, track addresses in insertion order so we can
        // rebuild the address book deterministically.
        let mut pending_assignments: BTreeMap<ActorId, EthAddress> = BTreeMap::new();
        for (i, line_result) in reader.lines().enumerate() {
            let line_number = i + 1;
            let line = line_result.map_err(|source| StateError::Io {
                path: path.to_path_buf(),
                source,
            })?;
            if line.trim().is_empty() {
                continue;
            }
            let record: StateRecord =
                serde_json::from_str(&line).map_err(|e| StateError::Malformed {
                    line_number,
                    message: format!("JSON parse: {e}"),
                })?;
            match record {
                StateRecord::Forwarded {
                    block_hash,
                    tx_hash,
                    log_index,
                } => {
                    let bh: TopicHash =
                        block_hash.0.try_into().map_err(|_| StateError::Malformed {
                            line_number,
                            message: "block_hash must be 32 bytes".into(),
                        })?;
                    let th: TopicHash =
                        tx_hash.0.try_into().map_err(|_| StateError::Malformed {
                            line_number,
                            message: "tx_hash must be 32 bytes".into(),
                        })?;
                    state.forwarded.insert(ForwardedKey {
                        block_hash: bh,
                        tx_hash: th,
                        log_index,
                    });
                }
                StateRecord::Confirmed { block_number } => {
                    state.last_confirmed_block = Some(block_number);
                }
                StateRecord::AddressAssigned { address, actor_id } => {
                    let bytes: [u8; 20] =
                        address.0.try_into().map_err(|_| StateError::Malformed {
                            line_number,
                            message: "address must be 20 bytes".into(),
                        })?;
                    let addr = EthAddress(bytes);
                    pending_assignments.insert(actor_id, addr);
                }
            }
        }
        // Reconstruct the address book by replaying assignments
        // in actor-id order.  The order matters because Lean's
        // `assign` issues ids monotonically; we must reproduce
        // the same mapping.
        for (_id, addr) in &pending_assignments {
            let (_id_assigned, _is_new) = state.address_book.assign(addr);
        }
        Ok(state)
    }

    /// Append a record to the state file and flush.  Each call
    /// is fsync-bounded; durability is "the OS thinks it's
    /// written" (no explicit `sync_data` is called per record to
    /// keep latency low).  RH-E.0 will add a proper transactional
    /// boundary.
    ///
    /// # Errors
    ///
    /// Returns `StateError::Io` on write failure.
    pub fn append(&mut self, record: &StateRecord) -> Result<(), StateError> {
        let line = serde_json::to_string(record).map_err(|e| StateError::Io {
            path: self.path.clone(),
            source: std::io::Error::new(std::io::ErrorKind::InvalidData, e),
        })?;
        self.writer
            .write_all(line.as_bytes())
            .map_err(|source| StateError::Io {
                path: self.path.clone(),
                source,
            })?;
        self.writer
            .write_all(b"\n")
            .map_err(|source| StateError::Io {
                path: self.path.clone(),
                source,
            })?;
        self.writer.flush().map_err(|source| StateError::Io {
            path: self.path.clone(),
            source,
        })?;
        Ok(())
    }

    /// Path of the underlying state file.
    #[must_use]
    pub fn path(&self) -> &Path {
        &self.path
    }
}

#[cfg(test)]
mod tests {
    use super::{ForwardedKey, HexBytes, StateError, StateRecord, StateStore};
    use crate::action::{ActorId, EthAddress};

    /// `HexBytes` round-trips through JSON.
    #[test]
    fn hex_bytes_round_trip() {
        let hb = HexBytes(vec![0x00, 0xff, 0xab, 0xcd]);
        let s = serde_json::to_string(&hb).unwrap();
        assert_eq!(s, "\"0x00ffabcd\"");
        let parsed: HexBytes = serde_json::from_str(&s).unwrap();
        assert_eq!(parsed, hb);
    }

    /// `HexBytes` rejects malformed input.
    #[test]
    fn hex_bytes_rejects_malformed() {
        assert!(serde_json::from_str::<HexBytes>("\"no_prefix\"").is_err());
        assert!(serde_json::from_str::<HexBytes>("\"0xZZ\"").is_err());
        assert!(serde_json::from_str::<HexBytes>("\"0x0\"").is_err()); // odd length
    }

    /// Round-trip `Forwarded` record through JSON.
    #[test]
    fn forwarded_record_round_trip() {
        let r = StateRecord::Forwarded {
            block_hash: HexBytes(vec![0xaa; 32]),
            tx_hash: HexBytes(vec![0xbb; 32]),
            log_index: 5,
        };
        let s = serde_json::to_string(&r).unwrap();
        let parsed: StateRecord = serde_json::from_str(&s).unwrap();
        assert_eq!(parsed, r);
        // Check JSON shape contains the discriminator field.
        assert!(s.contains("\"event\":\"forwarded\""));
    }

    /// Round-trip `Confirmed` record.
    #[test]
    fn confirmed_record_round_trip() {
        let r = StateRecord::Confirmed { block_number: 42 };
        let s = serde_json::to_string(&r).unwrap();
        let parsed: StateRecord = serde_json::from_str(&s).unwrap();
        assert_eq!(parsed, r);
    }

    /// Round-trip `AddressAssigned` record.
    #[test]
    fn address_assigned_record_round_trip() {
        let r = StateRecord::AddressAssigned {
            address: HexBytes(vec![0xcd; 20]),
            actor_id: 7,
        };
        let s = serde_json::to_string(&r).unwrap();
        let parsed: StateRecord = serde_json::from_str(&s).unwrap();
        assert_eq!(parsed, r);
    }

    /// `StateStore::open` on a non-existent path returns an
    /// empty state and creates the file.
    #[test]
    fn open_creates_new_file() {
        let temp = tempfile::tempdir().unwrap();
        let path = temp.path().join("state.jsonl");
        assert!(!path.exists());
        let (_store, state) = StateStore::open(&path).unwrap();
        assert!(path.exists());
        assert!(state.last_confirmed_block.is_none());
        assert!(state.forwarded.is_empty());
        assert_eq!(state.address_book.next_actor_id(), 1);
    }

    /// Append + replay round-trips state.
    #[test]
    fn append_replay_round_trip() {
        let temp = tempfile::tempdir().unwrap();
        let path = temp.path().join("state.jsonl");
        {
            let (mut store, _) = StateStore::open(&path).unwrap();
            store
                .append(&StateRecord::Confirmed { block_number: 100 })
                .unwrap();
            store
                .append(&StateRecord::Forwarded {
                    block_hash: HexBytes(vec![0x11; 32]),
                    tx_hash: HexBytes(vec![0x22; 32]),
                    log_index: 3,
                })
                .unwrap();
            store
                .append(&StateRecord::AddressAssigned {
                    address: HexBytes(vec![0xab; 20]),
                    actor_id: 1,
                })
                .unwrap();
        }
        let (_, state) = StateStore::open(&path).unwrap();
        assert_eq!(state.last_confirmed_block, Some(100));
        assert_eq!(state.forwarded.len(), 1);
        let key = ForwardedKey {
            block_hash: [0x11; 32],
            tx_hash: [0x22; 32],
            log_index: 3,
        };
        assert!(state.forwarded.contains(&key));
        // Address book has the assigned mapping.
        let addr = EthAddress::from_bytes(&[0xab; 20]).unwrap();
        assert_eq!(state.address_book.lookup(&addr), Some(1));
        // Address book's next_actor_id reflects the replayed
        // single assignment.
        assert_eq!(state.address_book.next_actor_id(), 2);
    }

    /// Multiple `Confirmed` records: last one wins.
    #[test]
    fn confirmed_overrides() {
        let temp = tempfile::tempdir().unwrap();
        let path = temp.path().join("state.jsonl");
        {
            let (mut store, _) = StateStore::open(&path).unwrap();
            store
                .append(&StateRecord::Confirmed { block_number: 50 })
                .unwrap();
            store
                .append(&StateRecord::Confirmed { block_number: 100 })
                .unwrap();
            store
                .append(&StateRecord::Confirmed { block_number: 75 })
                .unwrap();
        }
        let (_, state) = StateStore::open(&path).unwrap();
        assert_eq!(state.last_confirmed_block, Some(75));
    }

    /// Address-book replay preserves assignment order.
    #[test]
    fn address_book_replay_order() {
        let temp = tempfile::tempdir().unwrap();
        let path = temp.path().join("state.jsonl");
        {
            let (mut store, _) = StateStore::open(&path).unwrap();
            store
                .append(&StateRecord::AddressAssigned {
                    address: HexBytes(vec![0x01; 20]),
                    actor_id: 1,
                })
                .unwrap();
            store
                .append(&StateRecord::AddressAssigned {
                    address: HexBytes(vec![0x02; 20]),
                    actor_id: 2,
                })
                .unwrap();
            store
                .append(&StateRecord::AddressAssigned {
                    address: HexBytes(vec![0x03; 20]),
                    actor_id: 3,
                })
                .unwrap();
        }
        let (_, state) = StateStore::open(&path).unwrap();
        assert_eq!(state.address_book.len(), 3);
        assert_eq!(
            state
                .address_book
                .lookup(&EthAddress::from_bytes(&[0x01; 20]).unwrap()),
            Some(1)
        );
        assert_eq!(
            state
                .address_book
                .lookup(&EthAddress::from_bytes(&[0x02; 20]).unwrap()),
            Some(2)
        );
        assert_eq!(
            state
                .address_book
                .lookup(&EthAddress::from_bytes(&[0x03; 20]).unwrap()),
            Some(3)
        );
    }

    /// Empty lines in the state file are skipped silently.
    #[test]
    fn empty_lines_skipped() {
        let temp = tempfile::tempdir().unwrap();
        let path = temp.path().join("state.jsonl");
        std::fs::write(
            &path,
            "\n\n{\"event\":\"confirmed\",\"block_number\":42}\n\n\n",
        )
        .unwrap();
        let (_, state) = StateStore::open(&path).unwrap();
        assert_eq!(state.last_confirmed_block, Some(42));
    }

    /// A malformed line yields `StateError::Malformed`.
    #[test]
    fn malformed_line_returns_error() {
        let temp = tempfile::tempdir().unwrap();
        let path = temp.path().join("state.jsonl");
        std::fs::write(&path, "{not json}\n").unwrap();
        match StateStore::open(&path) {
            Err(StateError::Malformed { line_number, .. }) => {
                assert_eq!(line_number, 1);
            }
            other => panic!("expected Malformed error, got {other:?}"),
        }
    }

    /// Forwarded record with wrong-size block hash yields
    /// `Malformed`.
    #[test]
    fn wrong_size_block_hash_returns_error() {
        let temp = tempfile::tempdir().unwrap();
        let path = temp.path().join("state.jsonl");
        // 31-byte block hash instead of 32.
        let hex31 = "0x".to_string() + &"00".repeat(31);
        let hex32 = "0x".to_string() + &"00".repeat(32);
        let line = format!(
            r#"{{"event":"forwarded","block_hash":"{hex31}","tx_hash":"{hex32}","log_index":0}}"#
        );
        std::fs::write(&path, line + "\n").unwrap();
        match StateStore::open(&path) {
            Err(StateError::Malformed { message, .. }) => {
                assert!(message.contains("block_hash"));
            }
            other => panic!("expected Malformed error, got {other:?}"),
        }
    }

    /// Two `ForwardedKey`s with the same fields are equal.
    #[test]
    fn forwarded_key_equality() {
        let k1 = ForwardedKey {
            block_hash: [1u8; 32],
            tx_hash: [2u8; 32],
            log_index: 3,
        };
        let k2 = ForwardedKey {
            block_hash: [1u8; 32],
            tx_hash: [2u8; 32],
            log_index: 3,
        };
        assert_eq!(k1, k2);
    }

    /// `actor_id` is the same `u64`-typed `ActorId`.
    #[test]
    fn actor_id_type_check() {
        let _: ActorId = 0;
    }
}
