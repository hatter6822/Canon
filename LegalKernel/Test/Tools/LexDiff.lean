/-
  Canon  - A Societal Kernel
  Copyright (C) 2026  Adam Hall
  This program comes with ABSOLUTELY NO WARRANTY.
  This is free software, and you are welcome to redistribute it
  under certain conditions. See: https://github.com/hatter6822/Orbcrypt/blob/main/LICENSE
-/

/-
LegalKernel.Test.Tools.LexDiff — Workstream-LX (M3) tests for the
`lex_diff` binary.

Covers LX.34 / LX.35 (post-M3-completion API):

  * `LawDiff` per-clause `Option Diff` shape.
  * Per-clause structural diff detection.
  * Reformatting invariance (whitespace-only changes produce
    empty diffs).
  * Version-bump classifier: `patch` / `minor` / `major` /
    `none_` per the canonical scenarios in §14.2.
  * Refinement-proof obligation (L016).
  * Version-declaration mismatch (L007).
  * Deployment-level diff (added / removed / modified laws).
  * `checkRefinementProof : LawDecl → IO Bool` named-API.
  * `checkVersionDeclaration : LawDiff → Except Diagnostic Unit`
    named-API.
-/

import LegalKernel.Test.Framework
import Tools.LexDiff

namespace LegalKernel.Test.Tools
namespace LexDiffTests

open LegalKernel.Test
open LegalKernel.Tools.Lex
open LegalKernel.Tools.Lex.Diff

/-! ## Fixtures: hand-built `LawDecl` values -/

/-- A canonical `LawDecl` for testing.  Keep the fixture small so
    test assertions are easy to read. -/
def fixtureLawDecl : LawDecl := {
  schemaVersion := 1,
  identifier := "example.transfer",
  version := "1.0.0",
  actionIndex := 17,
  intent := "Move balance between actors at a resource.",
  params := [],
  signedBy := { name := "sender" },
  authorizedBy := { expr := "(fun _ _ => True)" },
  preExpr := "amount > 0",
  implBlock := "fun s => s",
  satisfies := [{ name := "conservative", args := [] }],
  eventsBlock := "[]",
  registryEffect := .none_,
  proofOverrides := [],
  sourceLocation := { fileName := "<test>", startPos := { line := 1, column := 0 } }
}

/-! ## LX.34 — clause-diff detection -/

/-- Two equal `LawDecl`s produce a diff with all `Option Diff`s
    set to `none`. -/
def emptyDiffOnEqual : TestCase := {
  name := "LX.34: equal LawDecls produce all-none clause diffs"
  body := do
    let diff := computeLawDiff fixtureLawDecl fixtureLawDecl
    assert diff.isEmpty "diff is empty (all clauses unchanged)"
}

/-- A `pre` change produces exactly `preDiff = some _`. -/
def preChangeDiff : TestCase := {
  name := "LX.34: pre change populates preDiff"
  body := do
    let after := { fixtureLawDecl with
      preExpr := "amount > 0 ∧ amount ≤ 2^32" }
    let diff := computeLawDiff fixtureLawDecl after
    assert diff.preDiff.isSome "preDiff is some"
    assert diff.implDiff.isNone "implDiff is none"
}

/-- An `intent` change produces `intentDiff`. -/
def intentChangeDiff : TestCase := {
  name := "LX.34: intent change populates intentDiff"
  body := do
    let after := { fixtureLawDecl with
      intent := "Move balance with new constraint." }
    let diff := computeLawDiff fixtureLawDecl after
    assert diff.intentDiff.isSome "intentDiff is some"
    assert diff.preDiff.isNone "preDiff is none"
}

/-- An `action_index` change produces `actionIndexDiff`. -/
def actionIndexChangeDiff : TestCase := {
  name := "LX.34: action_index change populates actionIndexDiff"
  body := do
    let after := { fixtureLawDecl with actionIndex := 18 }
    let diff := computeLawDiff fixtureLawDecl after
    assert diff.actionIndexDiff.isSome "actionIndexDiff is some"
}

/-- Multiple clause changes produce multiple diffs. -/
def multipleClauseChangeDiff : TestCase := {
  name := "LX.34: multiple clause changes produce multiple Option Diffs"
  body := do
    let after := { fixtureLawDecl with
      preExpr := "amount > 5",
      implBlock := "fun s => setBalance s 0 0 0",
      intent := "completely rewritten" }
    let diff := computeLawDiff fixtureLawDecl after
    assert diff.preDiff.isSome "preDiff is some"
    assert diff.implDiff.isSome "implDiff is some"
    assert diff.intentDiff.isSome "intentDiff is some"
    assert diff.actionIndexDiff.isNone "actionIndexDiff is none"
}

/-! ## LX.35 — version-bump classifier -/

/-- Equal LawDecls classify as `.none_`. -/
def classifyNoneOnEqual : TestCase := {
  name := "LX.35: classifyVersionBump returns .none_ on equal inputs"
  body := do
    let bump := classifyVersionBump fixtureLawDecl fixtureLawDecl
    assertEq (expected := VersionBump.none_) (actual := bump) "bump = none_"
}

/-- Pre-only change classifies as `.minor`. -/
def classifyMinorOnPreOnly : TestCase := {
  name := "LX.35: classifyVersionBump returns .minor on pre-only change"
  body := do
    let after := { fixtureLawDecl with
      preExpr := "amount > 0 ∧ amount ≤ 2^32" }
    let bump := classifyVersionBump fixtureLawDecl after
    assertEq (expected := VersionBump.minor) (actual := bump) "minor"
}

/-- Satisfies-additions-only classifies as `.minor`. -/
def classifyMinorOnSatisfiesAdditions : TestCase := {
  name := "LX.35: classifyVersionBump returns .minor on satisfies additions"
  body := do
    let after := { fixtureLawDecl with
      satisfies := fixtureLawDecl.satisfies ++ [{ name := "monotonic", args := [] }] }
    let bump := classifyVersionBump fixtureLawDecl after
    assertEq (expected := VersionBump.minor) (actual := bump) "minor"
}

/-- Proof-only change classifies as `.patch`. -/
def classifyPatchOnProofOnly : TestCase := {
  name := "LX.35: classifyVersionBump returns .patch on proof-only change"
  body := do
    let after := { fixtureLawDecl with
      proofOverrides := [{ property := "conservative",
                           tacticBlock := "by simp" }] }
    let bump := classifyVersionBump fixtureLawDecl after
    assertEq (expected := VersionBump.patch) (actual := bump) "patch"
}

/-- Impl change classifies as `.major`. -/
def classifyMajorOnImplChange : TestCase := {
  name := "LX.35: classifyVersionBump returns .major on impl change"
  body := do
    let after := { fixtureLawDecl with
      implBlock := "fun s => setBalance s 99 99 0" }
    let bump := classifyVersionBump fixtureLawDecl after
    assertEq (expected := VersionBump.major) (actual := bump) "major"
}

/-- Signed-by change classifies as `.major`. -/
def classifyMajorOnSignedByChange : TestCase := {
  name := "LX.35: classifyVersionBump returns .major on signed_by change"
  body := do
    let after := { fixtureLawDecl with
      signedBy := { name := "different_actor" } }
    let bump := classifyVersionBump fixtureLawDecl after
    assertEq (expected := VersionBump.major) (actual := bump) "major"
}

/-- Satisfies-removal classifies as `.major`. -/
def classifyMajorOnSatisfiesRemoval : TestCase := {
  name := "LX.35: classifyVersionBump returns .major on satisfies removal"
  body := do
    let before := { fixtureLawDecl with
      satisfies := [{ name := "conservative", args := [] },
                    { name := "monotonic", args := [] }] }
    let after := { fixtureLawDecl with
      satisfies := [{ name := "conservative", args := [] }] }
    let bump := classifyVersionBump before after
    assertEq (expected := VersionBump.major) (actual := bump) "major"
}

/-! ## LX.35 — refinement proof check (L016) -/

/-- A LawDecl with the matching refinement proof has the proof. -/
def refinementProofPresent : TestCase := {
  name := "LX.35: hasRefinementProof returns true when proof is present"
  body := do
    let after := { fixtureLawDecl with
      proofOverrides := [{ property := "refinement_v1_0",
                           tacticBlock := "by intro h; exact h.left" }] }
    assert (hasRefinementProof "1.0.0" after)
      "refinement_v1_0 should be present"
}

/-- A LawDecl with no refinement proof returns false. -/
def refinementProofMissing : TestCase := {
  name := "LX.35: hasRefinementProof returns false when proof is missing"
  body := do
    assert (!hasRefinementProof "1.0.0" fixtureLawDecl)
      "refinement_v1_0 should be missing"
}

/-- The expected refinement proof name is `refinement_v<MAJ>_<MIN>`. -/
def refinementProofNameShape : TestCase := {
  name := "LX.35: refinementProofName produces refinement_v<MAJ>_<MIN>"
  body := do
    assertEq (expected := "refinement_v1_0")
             (actual := refinementProofName "1.0.0") "1.0.0"
    assertEq (expected := "refinement_v2_3")
             (actual := refinementProofName "2.3.4") "2.3.4"
}

/-! ## LX.35 — Named-API tests -/

/-- `checkRefinementProof : String → LawDecl → IO Bool` returns
    the same result as `hasRefinementProof`. -/
def checkRefinementProofIO : TestCase := {
  name := "LX.35: checkRefinementProof IO wrapper matches hasRefinementProof"
  body := do
    let after := { fixtureLawDecl with
      proofOverrides := [{ property := "refinement_v1_0",
                           tacticBlock := "by exact h.left" }] }
    let result ← checkRefinementProof "1.0.0" after
    assert result "checkRefinementProof returns true"
    let result2 ← checkRefinementProof "1.0.0" fixtureLawDecl
    assert (!result2) "checkRefinementProof returns false on missing proof"
}

/-- `checkVersionDeclaration` returns `.ok ()` when declared bump
    matches computed. -/
def checkVersionDeclarationOk : TestCase := {
  name := "LX.35: checkVersionDeclaration .ok on matching bumps"
  body := do
    let after := { fixtureLawDecl with
      version := "1.1.0",
      preExpr := "amount > 0 ∧ amount ≤ 2^32",
      proofOverrides := [{ property := "refinement_v1_0",
                           tacticBlock := "by exact h.left" }] }
    match checkVersionDeclaration "<test>" fixtureLawDecl after with
    | .ok () => pure ()
    | .error _ => throw (IO.userError "expected .ok, got .error")
}

/-- `checkVersionDeclaration` returns `.error` on mismatch. -/
def checkVersionDeclarationMismatch : TestCase := {
  name := "LX.35: checkVersionDeclaration .error on mismatch"
  body := do
    -- Declared as patch (1.0.0 → 1.0.1), but it's actually a minor (pre changed).
    let after := { fixtureLawDecl with
      version := "1.0.1",
      preExpr := "amount > 0 ∧ amount ≤ 2^32" }
    match checkVersionDeclaration "<test>" fixtureLawDecl after with
    | .ok () => throw (IO.userError "expected .error, got .ok")
    | .error d => do
        assertEq (expected := "L007") (actual := d.code) "L007 fired"
}

/-! ## Manifest-level deployment diff -/

/-- Computing a deployment-diff with a single law unchanged
    produces an empty diff. -/
def deploymentDiffEmptyOnEqual : TestCase := {
  name := "LX.34: deployment-diff is empty when both refs equal"
  body := do
    let diff := computeDeploymentDiff [fixtureLawDecl] [fixtureLawDecl]
    assertEq (expected := 0) (actual := diff.lawsAdded.length) "0 added"
    assertEq (expected := 0) (actual := diff.lawsRemoved.length) "0 removed"
    assertEq (expected := 0) (actual := diff.lawsModified.length) "0 modified"
}

/-- A new law in the after-list shows up in `lawsAdded`. -/
def deploymentDiffAdded : TestCase := {
  name := "LX.34: deployment-diff detects added laws"
  body := do
    let added := { fixtureLawDecl with
      identifier := "example.new_law", actionIndex := 18 }
    let diff := computeDeploymentDiff [fixtureLawDecl]
                                       [fixtureLawDecl, added]
    assertEq (expected := 1) (actual := diff.lawsAdded.length) "1 added"
    assertEq (expected := "example.new_law")
             (actual := diff.lawsAdded.head!) "added law id"
}

/-- A removed law in the after-list shows up in `lawsRemoved`. -/
def deploymentDiffRemoved : TestCase := {
  name := "LX.34: deployment-diff detects removed laws"
  body := do
    let removed := { fixtureLawDecl with
      identifier := "example.sunset_law", actionIndex := 99 }
    let diff := computeDeploymentDiff [fixtureLawDecl, removed]
                                       [fixtureLawDecl]
    assertEq (expected := 1) (actual := diff.lawsRemoved.length) "1 removed"
}

/-- A modified law shows up in `lawsModified`. -/
def deploymentDiffModified : TestCase := {
  name := "LX.34: deployment-diff detects modified laws"
  body := do
    let after := { fixtureLawDecl with
      version := "1.1.0",
      preExpr := "amount > 0 ∧ amount ≤ 2^32" }
    let diff := computeDeploymentDiff [fixtureLawDecl] [after]
    assertEq (expected := 1) (actual := diff.lawsModified.length) "1 modified"
    let modified := diff.lawsModified.head!
    assertEq (expected := "1.0.0") (actual := modified.versionBefore) "before"
    assertEq (expected := "1.1.0") (actual := modified.versionAfter) "after"
    assertEq (expected := VersionBump.minor) (actual := modified.versionBump) "minor"
}

/-! ## Manifest-level diff classification (LX.35) -/

/-- Adding/removing laws triggers a major manifest bump. -/
def manifestBumpMajorOnLawAdd : TestCase := {
  name := "LX.35: adding a law triggers major manifest bump"
  body := do
    let added := { fixtureLawDecl with identifier := "ex.new" }
    let diff := computeDeploymentDiff [fixtureLawDecl] [fixtureLawDecl, added]
    match diff.classifyManifestBump with
    | some VersionBump.major => pure ()
    | _ => throw (IO.userError "expected major manifest bump")
}

/-- Empty diff produces no manifest bump. -/
def manifestBumpNoneOnEqual : TestCase := {
  name := "LX.35: equal manifests produce no manifest bump"
  body := do
    let diff := computeDeploymentDiff [fixtureLawDecl] [fixtureLawDecl]
    match diff.classifyManifestBump with
    | none => pure ()
    | some _ => throw (IO.userError "expected no manifest bump")
}

/-! ## Output formatting -/

/-- A non-empty diff produces non-empty formatted output. -/
def formatLawDiffNonEmpty : TestCase := {
  name := "LX.34: formatLawDiff produces non-empty output for non-empty diff"
  body := do
    let after := { fixtureLawDecl with
      version := "1.1.0",
      preExpr := "amount > 0 ∧ amount ≤ 2^32" }
    let diff := computeDeploymentDiff [fixtureLawDecl] [after]
    let modified := diff.lawsModified.head!
    let output := formatLawDiff modified
    assert (!output.isEmpty) "format output is non-empty"
    assert (output.contains '\n') "format output contains newlines"
}

/-! ## Reformatting invariance -/

/-- JSON round-trip produces identical `LawDecl`s, hence empty
    diff. -/
def reformattingProducesEmptyDiff : TestCase := {
  name := "LX.34: reformatting-only diff is empty (structural)"
  body := do
    let json := LawDecl.toCanonicalJson fixtureLawDecl
    match LawDecl.fromJson json with
    | .ok decoded =>
      let diff := computeLawDiff fixtureLawDecl decoded
      assert diff.isEmpty "round-tripped diff is empty"
    | .error msg =>
      throw (IO.userError s!"unexpected decode failure: {msg}")
}

/-! ## VersionBump display -/

/-- `VersionBump.toDisplay` returns canonical strings. -/
def versionBumpToDisplay : TestCase := {
  name := "LX.35: VersionBump.toDisplay strings"
  body := do
    assertEq (expected := "none") (actual := VersionBump.none_.toDisplay) "none"
    assertEq (expected := "patch") (actual := VersionBump.patch.toDisplay) "patch"
    assertEq (expected := "minor") (actual := VersionBump.minor.toDisplay) "minor"
    assertEq (expected := "major") (actual := VersionBump.major.toDisplay) "major"
}

/-! ## Audit-amendment: manifest-level diffing tests
    (LX.35 spec — the previously-empty authority/claim diff fields). -/

/-- A canonical `Deployment` for testing. -/
def fixtureDeployment : LegalKernel.DSL.Deployment := {
  identifier := "ex.test",
  deploymentId := ByteArray.mk (Array.replicate 32 (0 : UInt8)),
  version := "1.0.0",
  resources := [("USD", 0)],
  laws := [{ localName := "Transfer",
             lawIdent := Lean.Name.anonymous,
             version := "1.0.0" }],
  authority := [{ localName := "default",
                  policyExpr := "AuthorityPolicy.unrestricted" }],
  invariantClaims := [],
  manifestHashBytes := ByteArray.mk #[0]
}

/-- Equal `Deployment`s produce an empty manifest diff. -/
def manifestDiffEmptyOnEqual : TestCase := {
  name := "audit: computeManifestDiff is empty when both equal"
  body := do
    let diff := computeManifestDiff fixtureDeployment fixtureDeployment
    assertEq (expected := 0) (actual := diff.lawsAdded.length) "0 added"
    assertEq (expected := 0) (actual := diff.lawsRemoved.length) "0 removed"
    assertEq (expected := 0) (actual := diff.authoritySlotsAdded.length) "0 auth added"
    assertEq (expected := 0) (actual := diff.authoritySlotsRemoved.length) "0 auth removed"
    assertEq (expected := 0) (actual := diff.authoritySlotsModified.length) "0 auth modified"
    assertEq (expected := 0) (actual := diff.invariantClaimsAdded.length) "0 claims added"
    assertEq (expected := 0) (actual := diff.invariantClaimsRemoved.length) "0 claims removed"
}

/-- Adding an authority slot is detected. -/
def manifestDiffAuthorityAdded : TestCase := {
  name := "audit: computeManifestDiff detects added authority slots"
  body := do
    let after := { fixtureDeployment with
      authority := fixtureDeployment.authority ++
                   [{ localName := "extra_policy",
                      policyExpr := "AuthorityPolicy.empty" }] }
    let diff := computeManifestDiff fixtureDeployment after
    assertEq (expected := 1) (actual := diff.authoritySlotsAdded.length) "1 added"
    assertEq (expected := "extra_policy")
             (actual := diff.authoritySlotsAdded.head!) "added slot"
}

/-- Removing an authority slot is detected. -/
def manifestDiffAuthorityRemoved : TestCase := {
  name := "audit: computeManifestDiff detects removed authority slots"
  body := do
    let before := { fixtureDeployment with
      authority := fixtureDeployment.authority ++
                   [{ localName := "to_remove",
                      policyExpr := "AuthorityPolicy.empty" }] }
    let diff := computeManifestDiff before fixtureDeployment
    assertEq (expected := 1) (actual := diff.authoritySlotsRemoved.length) "1 removed"
}

/-- Modifying an authority slot's policy expression is detected. -/
def manifestDiffAuthorityModified : TestCase := {
  name := "audit: computeManifestDiff detects modified authority slots"
  body := do
    let after := { fixtureDeployment with
      authority := [{ localName := "default",
                      policyExpr := "AuthorityPolicy.empty" }] }  -- different expr
    let diff := computeManifestDiff fixtureDeployment after
    assertEq (expected := 1) (actual := diff.authoritySlotsModified.length) "1 modified"
}

/-- Adding an invariant claim is detected. -/
def manifestDiffClaimsAdded : TestCase := {
  name := "audit: computeManifestDiff detects added invariant claims"
  body := do
    let after := { fixtureDeployment with
      invariantClaims := [{ kind := .monotonicLawSet,
                            scope := .explicit ["Transfer"] }] }
    let diff := computeManifestDiff fixtureDeployment after
    assertEq (expected := 1) (actual := diff.invariantClaimsAdded.length) "1 added"
}

/-- Modifying an invariant claim's law list is detected. -/
def manifestDiffClaimsModified : TestCase := {
  name := "audit: computeManifestDiff detects modified invariant claims"
  body := do
    let before := { fixtureDeployment with
      invariantClaims := [{ kind := .monotonicLawSet,
                            scope := .explicit ["Transfer"] }] }
    let after := { fixtureDeployment with
      invariantClaims := [{ kind := .monotonicLawSet,
                            scope := .explicit ["Transfer", "Mint"] }] }
    let diff := computeManifestDiff before after
    assertEq (expected := 1) (actual := diff.invariantClaimsModified.length) "1 modified"
}

/-- `combineManifestAndLawDiffs` correctly merges the two diff sources. -/
def combineDiffsTest : TestCase := {
  name := "audit: combineManifestAndLawDiffs merges manifest + per-law diffs"
  body := do
    let manifestDiff := { (computeManifestDiff fixtureDeployment fixtureDeployment) with
      authoritySlotsAdded := ["new_slot"] }
    let lawDiff : DeploymentDiff := {
      lawsAdded := [],
      lawsRemoved := [],
      lawsModified := [{
        identifier := "ex.test",
        versionBefore := "1.0.0",
        versionAfter := "1.1.0",
        versionBump := .minor,
        preDiff := some { before := "x", after := "y" },
        implDiff := none, satisfiesDiff := none, eventsDiff := none,
        intentDiff := none, signedByDiff := none, authDiff := none,
        actionIndexDiff := none, paramsDiff := none,
        proofOverridesDiff := none, registryEffectDiff := none,
        refinementProofPresent := false
      }],
      authoritySlotsAdded := [],
      authoritySlotsRemoved := [],
      authoritySlotsModified := [],
      invariantClaimsAdded := [],
      invariantClaimsRemoved := [],
      invariantClaimsModified := []
    }
    let combined := combineManifestAndLawDiffs manifestDiff lawDiff
    -- Manifest-level fields preserved from manifestDiff
    assertEq (expected := 1) (actual := combined.authoritySlotsAdded.length)
      "manifest auth fields preserved"
    -- Law-level fields taken from lawDiff
    assertEq (expected := 1) (actual := combined.lawsModified.length)
      "law-level fields taken from lawDiff"
}

/-! ## Audit-amendment: git ref security tests (LX.34 + audit). -/

/-- `isSafeGitRef` rejects flag-shaped refs. -/
def gitRefRejectsFlagInjection : TestCase := {
  name := "audit: isSafeGitRef rejects flag-shaped refs"
  body := do
    assert (!isSafeGitRef "--upload-pack=evil")
      "should reject --upload-pack=evil"
    assert (!isSafeGitRef "-rf")
      "should reject -rf"
    assert (!isSafeGitRef "--exec=cmd")
      "should reject --exec=cmd"
}

/-- `isSafeGitRef` rejects empty + control-char refs. -/
def gitRefRejectsControlChars : TestCase := {
  name := "audit: isSafeGitRef rejects empty + control-char refs"
  body := do
    assert (!isSafeGitRef "") "should reject empty"
    assert (!isSafeGitRef "ref\nwith\nnewlines") "should reject newlines"
    assert (!isSafeGitRef "ref\twith\ttabs") "should reject tabs"
}

/-- `isSafeGitRef` accepts canonical ref formats. -/
def gitRefAcceptsCanonical : TestCase := {
  name := "audit: isSafeGitRef accepts canonical ref formats"
  body := do
    assert (isSafeGitRef "main") "main branch"
    assert (isSafeGitRef "v1.0.0") "tag"
    assert (isSafeGitRef "feature/foo") "branch with slash"
    assert (isSafeGitRef "abc123def456") "hash"
    assert (isSafeGitRef "HEAD~1") "relative ref"
}

/-- `parseLawDeclFromGitRef` rejects unsafe refs without invoking git. -/
def gitRefValidationInParseLawDeclFromGitRef : TestCase := {
  name := "audit: parseLawDeclFromGitRef rejects unsafe refs"
  body := do
    -- This test verifies behavior; we expect an IO.userError.
    try
      let _ ← parseLawDeclFromGitRef "--evil-flag" "/dev/null"
      throw (IO.userError "expected IO.userError, got success")
    catch e =>
      let msg := e.toString
      let hasSecurityMsg := (msg.splitOn "unsafe").length > 1
      assert hasSecurityMsg s!"expected 'unsafe' in error msg; got `{msg}`"
}

/-! ## Combined test suite -/

/-- Complete LX.34/LX.35 test suite. -/
def tests : List TestCase :=
  [ emptyDiffOnEqual,
    preChangeDiff,
    intentChangeDiff,
    actionIndexChangeDiff,
    multipleClauseChangeDiff,
    classifyNoneOnEqual,
    classifyMinorOnPreOnly,
    classifyMinorOnSatisfiesAdditions,
    classifyPatchOnProofOnly,
    classifyMajorOnImplChange,
    classifyMajorOnSignedByChange,
    classifyMajorOnSatisfiesRemoval,
    refinementProofPresent,
    refinementProofMissing,
    refinementProofNameShape,
    checkRefinementProofIO,
    checkVersionDeclarationOk,
    checkVersionDeclarationMismatch,
    deploymentDiffEmptyOnEqual,
    deploymentDiffAdded,
    deploymentDiffRemoved,
    deploymentDiffModified,
    manifestBumpMajorOnLawAdd,
    manifestBumpNoneOnEqual,
    formatLawDiffNonEmpty,
    reformattingProducesEmptyDiff,
    versionBumpToDisplay,
    -- Audit-amendment: manifest-level diff tests
    manifestDiffEmptyOnEqual,
    manifestDiffAuthorityAdded,
    manifestDiffAuthorityRemoved,
    manifestDiffAuthorityModified,
    manifestDiffClaimsAdded,
    manifestDiffClaimsModified,
    combineDiffsTest,
    -- Audit-amendment: git ref security tests
    gitRefRejectsFlagInjection,
    gitRefRejectsControlChars,
    gitRefAcceptsCanonical,
    gitRefValidationInParseLawDeclFromGitRef ]

end LexDiffTests
end LegalKernel.Test.Tools
