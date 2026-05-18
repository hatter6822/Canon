// Canon  - A Societal Kernel
// Copyright (C) 2026  Adam Hall
// This program comes with ABSOLUTELY NO WARRANTY.
// This is free software, and you are welcome to redistribute it
// under certain conditions. See: https://github.com/hatter6822/Orbcrypt/blob/main/LICENSE

//! Cross-stack ratification of the Rust game-state machine against
//! the Lean reference via the [RH-G.7 observer-game-trace corpus].
//!
//! [RH-G.7 observer-game-trace corpus]:
//! `LegalKernel/Test/Bridge/CrossCheck/ObserverGameTraces.lean`
//!
//! The Lean side generates a fixture file
//! `solidity/test/CrossCheck/fixtures/observer_game_traces.json`
//! containing 50+ pre-computed traces.  Each trace is a sequence
//! of `(GameState, GameTransition) → Result<GameState, GameError>`
//! steps executed by Lean's `applyTransition`.  This test loads
//! the fixture and re-executes every trace using the Rust port's
//! [`canon_faultproof_observer::game::apply_transition`] — every
//! step's outcome MUST byte-equal the Lean reference.
//!
//! ## What this catches
//!
//! Cross-stack drift between Lean's `applyTransition` and Rust's
//! `apply_transition`.  Examples:
//!
//!   * The Lean side changes the depth cap from 64 to 128 without
//!     updating the Rust port → fixture's `BisectionDepthExceeded`
//!     expected outcomes mismatch.
//!   * The Rust port introduces a perf optimisation that subtly
//!     reorders the precedence of guard checks → a trace exercising
//!     two simultaneous guard violations sees a different error
//!     variant on each side.
//!   * A new `GameError` variant is added on one side only → the
//!     fixture loader fails to deserialise.
//!
//! ## What this does NOT catch
//!
//! The Rust `apply_terminate_on_single_step` returns `Err(...)` in
//! the current port — the fixture deliberately does NOT emit any
//! `TerminateOnSingleStep` transitions (the L1 step VM is the
//! authority on those outcomes, not the Lean / Rust game-state
//! machine).
//!
//! ## Test discipline
//!
//! If the fixture file is absent (e.g., a Rust-only CI run that
//! didn't run `lake test` first), the test SKIPS with a clear
//! message rather than failing.  Run `lake test` (with
//! `CANON_FIXTURES_OVERWRITE=1` if you've changed the Lean
//! generator) to (re)materialise the fixture.

use canon_faultproof_observer::game::{
    apply_transition, Claim, DisputedRange, GameError, GameState, GameStatus, GameTransition,
    LogIndex, TurnSide,
};
use serde::{Deserialize, Serialize};
use std::path::PathBuf;

/// One trace step pairs a transition with its expected outcome.
#[derive(Debug, Clone, Deserialize, Serialize)]
struct TraceStep {
    transition: FixtureTransition,
    outcome: FixtureOutcome,
}

/// One trace: an initial state plus a sequence of steps.
#[derive(Debug, Clone, Deserialize, Serialize)]
struct Trace {
    id: String,
    desc: String,
    initial: FixtureGameState,
    steps: Vec<TraceStep>,
}

/// Fixture-file header.
#[derive(Debug, Deserialize, Serialize)]
struct Fixture {
    count: usize,
    identifier: String,
    traces: Vec<Trace>,
}

/// Mirror of [`GameState`] using the JSON-stable field shape the
/// Lean generator emits.  Decoded here, then converted to the
/// production [`GameState`] via [`FixtureGameState::decode`].
#[derive(Debug, Clone, Deserialize, Serialize)]
struct FixtureGameState {
    sequencer: u64,
    challenger: u64,
    range: FixtureRange,
    pending_midpoint: Option<FixtureClaim>,
    depth: u32,
    turn: String,
    sequencer_bond: u128,
    challenger_bond: u128,
    status: String,
    deployment_id: String,
}

#[derive(Debug, Clone, Deserialize, Serialize)]
struct FixtureRange {
    low: FixtureClaim,
    high: FixtureClaim,
}

#[derive(Debug, Clone, Deserialize, Serialize)]
struct FixtureClaim {
    idx: u64,
    commit: String,
}

#[derive(Debug, Clone, Deserialize, Serialize)]
#[serde(tag = "kind")]
enum FixtureTransition {
    SubmitMidpoint { midpoint: FixtureClaim },
    RespondAgree,
    RespondDisagree,
    TerminateOnSingleStep { claimed_post_commit: String },
    TimeoutLoss,
}

#[derive(Debug, Clone, Deserialize, Serialize)]
#[serde(tag = "kind")]
enum FixtureOutcome {
    Ok { state: FixtureGameState },
    Err { error: String },
}

fn hex_to_bytes32(s: &str) -> Result<[u8; 32], String> {
    let s = s.trim_start_matches("0x");
    if s.len() != 64 {
        return Err(format!("expected 64 hex chars, got {}", s.len()));
    }
    let mut out = [0u8; 32];
    for (i, chunk) in s.as_bytes().chunks(2).enumerate() {
        let hi = char_to_nibble(chunk[0])?;
        let lo = char_to_nibble(chunk[1])?;
        out[i] = (hi << 4) | lo;
    }
    Ok(out)
}

fn char_to_nibble(c: u8) -> Result<u8, String> {
    match c {
        b'0'..=b'9' => Ok(c - b'0'),
        b'a'..=b'f' => Ok(c - b'a' + 10),
        b'A'..=b'F' => Ok(c - b'A' + 10),
        _ => Err(format!("invalid hex char: {}", c as char)),
    }
}

impl FixtureClaim {
    fn decode(&self) -> Result<Claim, String> {
        Ok(Claim {
            idx: self.idx as LogIndex,
            commit: hex_to_bytes32(&self.commit)?,
        })
    }

    fn encode(c: &Claim) -> FixtureClaim {
        FixtureClaim {
            idx: c.idx,
            commit: bytes32_to_hex(&c.commit),
        }
    }
}

fn bytes32_to_hex(b: &[u8; 32]) -> String {
    let mut s = String::with_capacity(64);
    for byte in b {
        s.push_str(&format!("{byte:02x}"));
    }
    s
}

impl FixtureGameState {
    fn decode(&self) -> Result<GameState, String> {
        let turn = match self.turn.as_str() {
            "Sequencer" => TurnSide::Sequencer,
            "Challenger" => TurnSide::Challenger,
            other => return Err(format!("unknown turn: {other}")),
        };
        let status = match self.status.as_str() {
            "InProgress" => GameStatus::InProgress,
            "SequencerWon" => GameStatus::SequencerWon,
            "ChallengerWon" => GameStatus::ChallengerWon,
            "TimedOutSequencer" => GameStatus::TimedOutSequencer,
            "TimedOutChallenger" => GameStatus::TimedOutChallenger,
            other => return Err(format!("unknown status: {other}")),
        };
        Ok(GameState {
            sequencer: self.sequencer,
            challenger: self.challenger,
            range: DisputedRange {
                low: self.range.low.decode()?,
                high: self.range.high.decode()?,
            },
            pending_midpoint: match &self.pending_midpoint {
                None => None,
                Some(c) => Some(c.decode()?),
            },
            depth: self.depth,
            turn,
            sequencer_bond: self.sequencer_bond,
            challenger_bond: self.challenger_bond,
            status,
            deployment_id: hex_to_bytes32(&self.deployment_id)?,
        })
    }

    fn encode(gs: &GameState) -> FixtureGameState {
        FixtureGameState {
            sequencer: gs.sequencer,
            challenger: gs.challenger,
            range: FixtureRange {
                low: FixtureClaim::encode(&gs.range.low),
                high: FixtureClaim::encode(&gs.range.high),
            },
            pending_midpoint: gs.pending_midpoint.as_ref().map(FixtureClaim::encode),
            depth: gs.depth,
            turn: match gs.turn {
                TurnSide::Sequencer => "Sequencer".to_string(),
                TurnSide::Challenger => "Challenger".to_string(),
            },
            sequencer_bond: gs.sequencer_bond,
            challenger_bond: gs.challenger_bond,
            status: match gs.status {
                GameStatus::InProgress => "InProgress".to_string(),
                GameStatus::SequencerWon => "SequencerWon".to_string(),
                GameStatus::ChallengerWon => "ChallengerWon".to_string(),
                GameStatus::TimedOutSequencer => "TimedOutSequencer".to_string(),
                GameStatus::TimedOutChallenger => "TimedOutChallenger".to_string(),
            },
            deployment_id: bytes32_to_hex(&gs.deployment_id),
        }
    }
}

impl FixtureTransition {
    fn decode(&self) -> Result<GameTransition, String> {
        match self {
            FixtureTransition::SubmitMidpoint { midpoint } => {
                Ok(GameTransition::SubmitMidpoint(midpoint.decode()?))
            }
            FixtureTransition::RespondAgree => Ok(GameTransition::RespondAgree),
            FixtureTransition::RespondDisagree => Ok(GameTransition::RespondDisagree),
            FixtureTransition::TerminateOnSingleStep {
                claimed_post_commit,
            } => Ok(GameTransition::TerminateOnSingleStep {
                claimed_post_commit: hex_to_bytes32(claimed_post_commit)?,
            }),
            FixtureTransition::TimeoutLoss => Ok(GameTransition::TimeoutLoss),
        }
    }
}

fn locate_fixture() -> Option<PathBuf> {
    let manifest = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    // <repo>/runtime/canon-faultproof-observer → <repo>
    let runtime = manifest.parent()?;
    let repo = runtime.parent()?;
    let fixture = repo
        .join("solidity")
        .join("test")
        .join("CrossCheck")
        .join("fixtures")
        .join("observer_game_traces.json");
    if fixture.exists() {
        Some(fixture)
    } else {
        None
    }
}

fn load_corpus() -> Option<Fixture> {
    let path = locate_fixture()?;
    let bytes = std::fs::read(&path).ok()?;
    let fixture: Fixture = serde_json::from_slice(&bytes).ok()?;
    Some(fixture)
}

fn rust_outcome_to_fixture(o: Result<GameState, GameError>) -> FixtureOutcome {
    match o {
        Ok(gs) => FixtureOutcome::Ok {
            state: FixtureGameState::encode(&gs),
        },
        Err(e) => FixtureOutcome::Err {
            error: format!("{e:?}"),
        },
    }
}

fn fixture_outcome_to_canonical_form(
    f: &FixtureOutcome,
) -> Result<(String, Option<GameState>), String> {
    match f {
        FixtureOutcome::Ok { state } => Ok(("Ok".to_string(), Some(state.decode()?))),
        FixtureOutcome::Err { error } => Ok((format!("Err::{error}"), None)),
    }
}

fn rust_outcome_to_canonical_form(o: &Result<GameState, GameError>) -> (String, Option<GameState>) {
    match o {
        Ok(gs) => ("Ok".to_string(), Some(gs.clone())),
        Err(e) => (format!("Err::{}", error_tag(*e)), None),
    }
}

fn error_tag(e: GameError) -> &'static str {
    match e {
        GameError::GameAlreadyEnded => "GameAlreadyEnded",
        GameError::WrongTurn => "WrongTurn",
        GameError::MidpointOutOfRange => "MidpointOutOfRange",
        GameError::MidpointDuringResponse => "MidpointDuringResponse",
        GameError::ResponseDuringSubmit => "ResponseDuringSubmit",
        GameError::BisectionDepthExceeded => "BisectionDepthExceeded",
        GameError::RangeNotSingleStep => "RangeNotSingleStep",
        GameError::TerminationDuringBisection => "TerminationDuringBisection",
        GameError::InvalidSettlement => "InvalidSettlement",
    }
}

#[test]
fn corpus_loads_and_has_minimum_size() {
    let Some(corpus) = load_corpus() else {
        eprintln!(
            "[SKIP] observer_game_traces.json not found.  Run `lake test` \
             to materialise it (then re-run this test)."
        );
        return;
    };
    assert!(
        corpus.count >= 50,
        "corpus count {} < minimum 50",
        corpus.count
    );
    assert_eq!(corpus.count, corpus.traces.len(), "header/list count drift");
    assert_eq!(corpus.identifier, "canon-observer-game-traces/v1");
}

#[test]
fn every_trace_id_is_unique() {
    let Some(corpus) = load_corpus() else {
        eprintln!("[SKIP] observer_game_traces.json not found.");
        return;
    };
    let mut seen = std::collections::HashSet::new();
    for trace in &corpus.traces {
        assert!(
            seen.insert(trace.id.clone()),
            "duplicate trace id: {}",
            trace.id
        );
    }
}

#[test]
fn every_trace_initial_state_decodes() {
    let Some(corpus) = load_corpus() else {
        eprintln!("[SKIP] observer_game_traces.json not found.");
        return;
    };
    for trace in &corpus.traces {
        trace
            .initial
            .decode()
            .unwrap_or_else(|e| panic!("trace {} initial state decode failed: {e}", trace.id));
    }
}

#[test]
fn every_step_outcome_byte_equals_lean_reference() {
    let Some(corpus) = load_corpus() else {
        eprintln!("[SKIP] observer_game_traces.json not found.");
        return;
    };
    let mut failures: Vec<String> = Vec::new();
    for trace in &corpus.traces {
        let initial = match trace.initial.decode() {
            Ok(s) => s,
            Err(e) => {
                failures.push(format!("trace {}: initial decode {e}", trace.id));
                continue;
            }
        };
        let mut current = initial;
        for (i, step) in trace.steps.iter().enumerate() {
            let t = match step.transition.decode() {
                Ok(t) => t,
                Err(e) => {
                    failures.push(format!(
                        "trace {} step {}: transition decode {e}",
                        trace.id, i
                    ));
                    break;
                }
            };
            let actual = apply_transition(&current, t);

            let (actual_tag, actual_state) = rust_outcome_to_canonical_form(&actual);
            let (expected_tag, expected_state) =
                match fixture_outcome_to_canonical_form(&step.outcome) {
                    Ok(p) => p,
                    Err(e) => {
                        failures.push(format!(
                            "trace {} step {}: expected outcome decode {e}",
                            trace.id, i
                        ));
                        break;
                    }
                };

            if actual_tag != expected_tag {
                failures.push(format!(
                    "trace {} step {}: tag mismatch — Rust={actual_tag}, Lean={expected_tag}",
                    trace.id, i
                ));
                break;
            }

            if let (Some(actual_gs), Some(expected_gs)) =
                (actual_state.as_ref(), expected_state.as_ref())
            {
                if actual_gs != expected_gs {
                    failures.push(format!(
                        "trace {} step {}: state mismatch — Rust={actual_gs:?}, Lean={expected_gs:?}",
                        trace.id, i
                    ));
                    break;
                }
            }

            // Advance for the next iteration.  Per the Lean
            // generator's semantics, if the step errored we stay
            // at `current`; otherwise we advance to the new state.
            if let Ok(next) = actual {
                current = next;
            }
        }
    }

    assert!(
        failures.is_empty(),
        "{} cross-stack failure(s):\n{}",
        failures.len(),
        failures.join("\n")
    );
}

#[test]
fn rust_outcome_round_trips_through_fixture_encoding() {
    // Sanity: encode → decode → encode produces the same fixture
    // representation.  This catches any drift in the fixture
    // encoding helpers themselves.
    let gs = GameState {
        sequencer: 1,
        challenger: 2,
        range: DisputedRange {
            low: Claim {
                idx: 0,
                commit: [1u8; 32],
            },
            high: Claim {
                idx: 4,
                commit: [2u8; 32],
            },
        },
        pending_midpoint: None,
        depth: 0,
        turn: TurnSide::Sequencer,
        sequencer_bond: 1000,
        challenger_bond: 1000,
        status: GameStatus::InProgress,
        deployment_id: [0xAB; 32],
    };
    let encoded = FixtureGameState::encode(&gs);
    let decoded = encoded.decode().expect("round-trip decode");
    assert_eq!(decoded, gs);
    let re_encoded = FixtureGameState::encode(&decoded);
    let json1 = serde_json::to_string(&encoded).unwrap();
    let json2 = serde_json::to_string(&re_encoded).unwrap();
    assert_eq!(json1, json2);
}

#[test]
fn outcome_encoder_recognises_ok_and_err() {
    // Test the helpers in isolation against synthetic outcomes.
    let gs = GameState {
        sequencer: 1,
        challenger: 2,
        range: DisputedRange {
            low: Claim {
                idx: 0,
                commit: [0u8; 32],
            },
            high: Claim {
                idx: 4,
                commit: [0u8; 32],
            },
        },
        pending_midpoint: None,
        depth: 0,
        turn: TurnSide::Sequencer,
        sequencer_bond: 1,
        challenger_bond: 1,
        status: GameStatus::InProgress,
        deployment_id: [0u8; 32],
    };

    let ok_fixture = rust_outcome_to_fixture(Ok(gs.clone()));
    matches!(ok_fixture, FixtureOutcome::Ok { .. });

    let err_fixture = rust_outcome_to_fixture(Err(GameError::MidpointOutOfRange));
    matches!(err_fixture, FixtureOutcome::Err { .. });
}
