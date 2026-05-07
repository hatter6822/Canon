/-
  Canon  - A Societal Kernel
  Copyright (C) 2026  Adam Hall
  This program comes with ABSOLUTELY NO WARRANTY.
  This is free software, and you are welcome to redistribute it
  under certain conditions. See: https://github.com/hatter6822/Orbcrypt/blob/main/LICENSE
-/

/-
LegalKernel.Test.Encoding.LocalPolicy — runtime tests for the
LP.2 LocalPolicy encoding.

Workstream LP work unit LP.2.  Exercises round-trip and
distinguishability properties of the CBE codec for
`LocalPolicyClause`, `LocalPolicy`, and `LocalPolicies`.
-/

import LegalKernel.Encoding.LocalPolicy
import LegalKernel.Test.Framework

open LegalKernel
open LegalKernel.Authority
open LegalKernel.Encoding
open LegalKernel.Test

namespace LegalKernel.Test.Encoding.LocalPolicyTests

/-! ## Test fixtures -/

/-- `denyTags [0, 1]` clause. -/
def cDeny : LocalPolicyClause := .denyTags [0, 1]

/-- `requireRecipientIn 1 [42]` clause. -/
def cRequire : LocalPolicyClause := .requireRecipientIn 1 [42]

/-- `capAmount 1 100` clause. -/
def cCap : LocalPolicyClause := .capAmount 1 100

/-- An empty policy. -/
def pEmpty : LocalPolicy := LocalPolicy.empty

/-- A 1-clause policy. -/
def pSingle : LocalPolicy := { clauses := [cDeny] }

/-- A 3-clause policy with all three variants. -/
def pTriple : LocalPolicy := { clauses := [cDeny, cRequire, cCap] }

/-! ## LP.2 test cases -/

/-- All LP.2 test cases. -/
def tests : List TestCase :=
  [ -- Round-trip per clause.
    { name := "denyTags round-trip"
    , body := do
        match Encodable.decode (T := LocalPolicyClause)
                (Encodable.encode (T := LocalPolicyClause) cDeny) with
        | .ok (c', []) =>
          if c' = cDeny then pure ()
          else throw <| IO.userError "denyTags round-trip mismatch"
        | _ => throw <| IO.userError "denyTags round-trip failed to decode"
    }
  , { name := "requireRecipientIn round-trip"
    , body := do
        match Encodable.decode (T := LocalPolicyClause)
                (Encodable.encode (T := LocalPolicyClause) cRequire) with
        | .ok (c', []) =>
          if c' = cRequire then pure ()
          else throw <| IO.userError "requireRecipientIn round-trip mismatch"
        | _ => throw <| IO.userError "requireRecipientIn round-trip failed to decode"
    }
  , { name := "capAmount round-trip"
    , body := do
        match Encodable.decode (T := LocalPolicyClause)
                (Encodable.encode (T := LocalPolicyClause) cCap) with
        | .ok (c', []) =>
          if c' = cCap then pure ()
          else throw <| IO.userError "capAmount round-trip mismatch"
        | _ => throw <| IO.userError "capAmount round-trip failed to decode"
    }
  , -- Round-trip per policy.
    { name := "empty policy round-trip"
    , body := do
        match Encodable.decode (T := LocalPolicy)
                (Encodable.encode (T := LocalPolicy) pEmpty) with
        | .ok (p, []) =>
          if p = pEmpty then pure ()
          else throw <| IO.userError "empty policy round-trip mismatch"
        | _ => throw <| IO.userError "empty policy round-trip failed"
    }
  , { name := "single-clause policy round-trip"
    , body := do
        match Encodable.decode (T := LocalPolicy)
                (Encodable.encode (T := LocalPolicy) pSingle) with
        | .ok (p, []) =>
          if p = pSingle then pure ()
          else throw <| IO.userError "single-clause policy round-trip mismatch"
        | _ => throw <| IO.userError "single-clause policy round-trip failed"
    }
  , { name := "3-clause policy round-trip"
    , body := do
        match Encodable.decode (T := LocalPolicy)
                (Encodable.encode (T := LocalPolicy) pTriple) with
        | .ok (p, []) =>
          if p = pTriple then pure ()
          else throw <| IO.userError "3-clause policy round-trip mismatch"
        | _ => throw <| IO.userError "3-clause policy round-trip failed"
    }
  , -- Cross-clause distinguishability.
    { name := "denyTags vs capAmount produce different bytes"
    , body := do
        let b1 := Encodable.encode (T := LocalPolicyClause) cDeny
        let b2 := Encodable.encode (T := LocalPolicyClause) cCap
        if b1 = b2 then
          throw <| IO.userError "distinct clauses produced identical bytes"
        else pure ()
    }
  , -- Determinism.
    { name := "policy encoding is deterministic"
    , body := do
        let b1 := Encodable.encode (T := LocalPolicy) pTriple
        let b2 := Encodable.encode (T := LocalPolicy) pTriple
        if b1 = b2 then pure ()
        else throw <| IO.userError "encoding non-deterministic"
    }
  , -- Spot-check encoded length is positive.
    { name := "encoded clause is non-empty"
    , body := do
        let b := Encodable.encode (T := LocalPolicyClause) cCap
        if b.length > 0 then pure ()
        else throw <| IO.userError "empty encoding"
    }
  , -- Term-level API stability for headline theorems.
    { name := "localPolicyClause_roundtrip API stability"
    , body := do
        let _proof :
          ∀ (c : LocalPolicyClause) (rest : Stream),
            LocalPolicyClause.fieldsBounded c →
            Encodable.decode (T := LocalPolicyClause)
              (Encodable.encode c ++ rest) = .ok (c, rest) :=
          localPolicyClause_roundtrip
        pure ()
    }
  , { name := "localPolicy_roundtrip API stability"
    , body := do
        let _proof :
          ∀ (p : LocalPolicy) (rest : Stream),
            LocalPolicy.fieldsBounded p →
            Encodable.decode (T := LocalPolicy)
              (Encodable.encode p ++ rest) = .ok (p, rest) :=
          localPolicy_roundtrip
        pure ()
    }
  , { name := "localPolicyClause_encode_injective API stability"
    , body := do
        let _proof :
          ∀ (c₁ c₂ : LocalPolicyClause),
            LocalPolicyClause.fieldsBounded c₁ →
            LocalPolicyClause.fieldsBounded c₂ →
            Encodable.encode (T := LocalPolicyClause) c₁ =
            Encodable.encode (T := LocalPolicyClause) c₂ →
            c₁ = c₂ :=
          localPolicyClause_encode_injective
        pure ()
    }
  ]

end LegalKernel.Test.Encoding.LocalPolicyTests
