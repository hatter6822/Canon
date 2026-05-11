/-
  Canon  - A Societal Kernel
  Copyright (C) 2026  Adam Hall
  This program comes with ABSOLUTELY NO WARRANTY.
  This is free software, and you are welcome to redistribute it
  under certain conditions. See: https://github.com/hatter6822/Orbcrypt/blob/main/LICENSE
-/

/-
LegalKernel.Test.FaultProof.Witness — type-level API stability
tests for the `FaultProofChallengerWon` propositional witness
(Workstream H WU H.4.4e + WU H.8.4).
-/

import LegalKernel.FaultProof.Witness
import LegalKernel.Test.Framework

open LegalKernel
open LegalKernel.FaultProof
open LegalKernel.Authority
open LegalKernel.Disputes
open LegalKernel.Runtime
open LegalKernel.Test

namespace LegalKernel.Test.FaultProof.Witness

/-- Tests for the `FaultProofChallengerWon` witness type's API. -/
def tests : List TestCase :=
  [ { name := "FaultProofChallengerWon API stable"
    , body := do
        -- Term-level API check: the structure has a constructor
        -- that accepts the documented fields.  Doesn't construct
        -- a witness at the value level (that would require an
        -- l1FaultProofVerifier opaque attestation).
        let _ := @FaultProofChallengerWon.of_log_entry
        pure ()
    }
  , { name := "FaultProofChallengerWon.logIdx_proj API stable"
    , body := do
        let _ := @FaultProofChallengerWon.logIdx_proj
        pure ()
    }
  , { name := "FaultProofChallengerWon.action_eq_proj API stable"
    , body := do
        let _ := @FaultProofChallengerWon.action_eq_proj
        pure ()
    }
  , { name := "l1FaultProofVerifier API stable (opaque present)"
    , body := do
        -- Just type-check that we can apply the opaque to its
        -- argument list without crashing the elaborator.
        let _ := l1FaultProofVerifier ByteArray.empty 0 0 0
        pure ()
    }
  ]

end LegalKernel.Test.FaultProof.Witness
