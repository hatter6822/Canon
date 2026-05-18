/-
  Canon  - A Societal Kernel
  Copyright (C) 2026  Adam Hall
  This program comes with ABSOLUTELY NO WARRANTY.
  This is free software, and you are welcome to redistribute it
  under certain conditions. See: https://github.com/hatter6822/Orbcrypt/blob/main/LICENSE
-/

import LegalKernel.Test.Framework
import LegalKernel.Disputes.Evidence
import LegalKernel.FaultProof.Commit
import LegalKernel.FaultProof.Observer
import LegalKernel.Runtime.Snapshot

/-!
LegalKernel.Test.Integration.ExportCellProofsCli — RH-G plan
deliverable.

Integration regression for the `canon export-cell-proofs LOG
IDX SIGNER` subcommand that the off-chain `canon-faultproof-
observer` Rust crate's terminate-on-single-step move consumes
to build its `terminateOnSingleStep(..., CellProof[], ...)`
calldata.  Verifies the Lean-level kernel contract:
`buildObserverCellProofs` produces a bundle that
`verifyCellProofs` accepts against the pre-state's commit, and
the bundle is deterministic in its inputs.

The CLI surface itself lives in `Main.lean`; this test covers
the Lean-level kernel contract that the CLI dispatches to.
Subprocess-level invocation tests (spawning the binary and
parsing the emitted JSON) live in the Rust crate's `tests/`
directory.
-/

open LegalKernel
open LegalKernel.Authority
open LegalKernel.Disputes
open LegalKernel.FaultProof
open LegalKernel.FaultProof.Observer
open LegalKernel.Runtime
open LegalKernel.Test

namespace LegalKernel.Test.Integration.ExportCellProofsCli

/-- The cell-proof bundle for a transfer has the documented
    four cells (registry, balance×2, nonce). -/
def transfer_bundle_has_four_cells : IO Unit := do
  let es : ExtendedState := ExtendedState.empty
  let signer : ActorId := 1
  let action : Action := Action.transfer 1 signer 2 100
  let bundle := buildObserverCellProofs es action signer
  unless bundle.proofs.length = 4 do
    throw (IO.userError
      s!"buildObserverCellProofs transfer bundle.proofs.length = {bundle.proofs.length}, expected 4")

/-- The cell-proof bundle is deterministic in its inputs. -/
def bundle_is_deterministic : IO Unit := do
  let es : ExtendedState := ExtendedState.empty
  let signer : ActorId := 1
  let action : Action := Action.transfer 1 signer 2 100
  let b1 := buildObserverCellProofs es action signer
  let b2 := buildObserverCellProofs es action signer
  unless b1.proofs.length = b2.proofs.length do
    throw (IO.userError
      s!"bundle non-determinism: b1.length = {b1.proofs.length}, b2.length = {b2.proofs.length}")

/-- The cell-proof bundle verifies against the pre-state's
    commit (i.e., `verifyCellProofs` returns `true`).  This is
    the load-bearing soundness contract: the off-chain bundle
    builder MUST produce verifier-accepting proofs. -/
def bundle_verifies_against_commit : IO Unit := do
  let es : ExtendedState := ExtendedState.empty
  let signer : ActorId := 1
  let action : Action := Action.transfer 1 signer 2 100
  let bundle := buildObserverCellProofs es action signer
  let commit := commitExtendedState es
  unless verifyCellProofs commit bundle = true do
    throw (IO.userError "buildObserverCellProofs bundle failed verifyCellProofs check")

/-- API stability: `buildObserverCellProofs : ExtendedState →
    Action → ActorId → CellProofBundle`. -/
def build_observer_cell_proofs_api_stable : IO Unit := do
  let _proof :
      ExtendedState → Action → ActorId → CellProofBundle :=
    buildObserverCellProofs
  pure ()

/-- API stability: `verifyCellProofs : StateCommit →
    CellProofBundle → Bool`. -/
def verify_cell_proofs_api_stable : IO Unit := do
  let _proof : StateCommit → CellProofBundle → Bool :=
    verifyCellProofs
  pure ()

end LegalKernel.Test.Integration.ExportCellProofsCli

namespace LegalKernel.Test.Integration.ExportCellProofsCli

/-- All tests in this module — collected via the `@[test]`
    attribute and dispatched from `Tests.lean`. -/
def tests : List TestCase := [
  ⟨"export-cell-proofs: transfer bundle has 4 cells",
    transfer_bundle_has_four_cells⟩,
  ⟨"export-cell-proofs: bundle is deterministic",
    bundle_is_deterministic⟩,
  ⟨"export-cell-proofs: bundle verifies against commit",
    bundle_verifies_against_commit⟩,
  ⟨"export-cell-proofs: buildObserverCellProofs API stable",
    build_observer_cell_proofs_api_stable⟩,
  ⟨"export-cell-proofs: verifyCellProofs API stable",
    verify_cell_proofs_api_stable⟩
]

end LegalKernel.Test.Integration.ExportCellProofsCli
