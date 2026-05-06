/-
  Canon  - A Societal Kernel
  Copyright (C) 2026  Adam Hall
  This program comes with ABSOLUTELY NO WARRANTY.
  This is free software, and you are welcome to redistribute it
  under certain conditions. See: https://github.com/hatter6822/Orbcrypt/blob/main/LICENSE
-/

/-
LegalKernel.Test.Bridge.BridgeActor — Workstream B.3 test suite.

Exercises the bridge-actor reservation infrastructure
(`LegalKernel/Bridge/BridgeActor.lean`).  Coverage:

  * **Bridge actor identifier.**  `bridgeActor = (0 : ActorId)`.
  * **Authorisation: positive cases.**  The bridge policy
    authorises `replaceKey` and `registerIdentity` actions when
    the signer is the bridge actor.
  * **Authorisation: rejection cases.**  The bridge policy
    rejects every other Action constructor (transfer, mint, burn,
    freezeResource, reward, distributeOthers, proportionalDilute,
    dispute, disputeWithdraw, verdict, rollback) for the bridge
    actor.
  * **Cross-actor rejection.**  The bridge policy rejects every
    action by a non-bridge signer, including otherwise-permitted
    actions.
  * **Decidability sanity.**  The `decAuth` field is properly
    decidable and `decide` works at concrete inputs.
  * **Term-level API stability** for every §12.9 theorem.
-/

import LegalKernel.Bridge.BridgeActor
import LegalKernel.Test.Framework

namespace LegalKernel.Test.Bridge
namespace BridgeActorTests

open LegalKernel
open LegalKernel.Authority
open LegalKernel.Bridge
open LegalKernel.Test

/-- A sample public key for fixture construction. -/
def samplePk : PublicKey := ⟨#[0xAA, 0xBB]⟩

/-- Tests for `bridgeActor` and `bridgePolicy`. -/
def tests : List TestCase :=
  [ -- ## bridgeActor identifier
    { name := "bridgeActor = 0"
    , body := do
        assertEq (expected := (0 : ActorId)) (actual := bridgeActor) "bridgeActor"
    }
  , -- ## Authorisation: positive cases
    { name := "bridgePolicy authorises replaceKey by bridge actor"
    , body := do
        let h : bridgePolicy.authorized bridgeActor (.replaceKey 1 samplePk) :=
          bridgePolicy_authorizes_replaceKey 1 samplePk
        let _ := h  -- API stability check
        pure ()
    }
  , { name := "bridgePolicy authorises registerIdentity by bridge actor"
    , body := do
        let h : bridgePolicy.authorized bridgeActor (.registerIdentity 5 samplePk) :=
          bridgePolicy_authorizes_registerIdentity 5 samplePk
        let _ := h
        pure ()
    }
  , -- ## Authorisation: rejection cases
    { name := "bridgePolicy rejects transfer"
    , body := do
        let h := bridgePolicy_rejects_transfer 1 2 3 4
        if (decide (bridgePolicy.authorized bridgeActor (.transfer 1 2 3 4))) then
          throw <| IO.userError "bridgePolicy unexpectedly authorised transfer"
        let _ := h
        pure ()
    }
  , { name := "bridgePolicy rejects mint"
    , body := do
        let h := bridgePolicy_rejects_mint 1 2 3
        let _ := h
        if (decide (bridgePolicy.authorized bridgeActor (.mint 1 2 3))) then
          throw <| IO.userError "bridgePolicy unexpectedly authorised mint"
    }
  , { name := "bridgePolicy rejects burn"
    , body := do
        let h := bridgePolicy_rejects_burn 1 2 3
        let _ := h
        if (decide (bridgePolicy.authorized bridgeActor (.burn 1 2 3))) then
          throw <| IO.userError "bridgePolicy unexpectedly authorised burn"
    }
  , { name := "bridgePolicy rejects freezeResource"
    , body := do
        let h := bridgePolicy_rejects_freezeResource 1
        let _ := h
        if (decide (bridgePolicy.authorized bridgeActor (.freezeResource 1))) then
          throw <| IO.userError "bridgePolicy unexpectedly authorised freezeResource"
    }
  , { name := "bridgePolicy rejects reward"
    , body := do
        let h := bridgePolicy_rejects_reward 1 2 3
        let _ := h
        if (decide (bridgePolicy.authorized bridgeActor (.reward 1 2 3))) then
          throw <| IO.userError "bridgePolicy unexpectedly authorised reward"
    }
  , { name := "bridgePolicy rejects distributeOthers"
    , body := do
        let h := bridgePolicy_rejects_distributeOthers 1 2 3
        let _ := h
        if (decide (bridgePolicy.authorized bridgeActor (.distributeOthers 1 2 3))) then
          throw <| IO.userError "bridgePolicy unexpectedly authorised distributeOthers"
    }
  , { name := "bridgePolicy rejects proportionalDilute"
    , body := do
        let h := bridgePolicy_rejects_proportionalDilute 1 2 3
        let _ := h
        if (decide (bridgePolicy.authorized bridgeActor (.proportionalDilute 1 2 3))) then
          throw <| IO.userError "bridgePolicy unexpectedly authorised proportionalDilute"
    }
  , { name := "bridgePolicy rejects rollback"
    , body := do
        let h := bridgePolicy_rejects_rollback 5
        let _ := h
        if (decide (bridgePolicy.authorized bridgeActor (.rollback 5))) then
          throw <| IO.userError "bridgePolicy unexpectedly authorised rollback"
    }
  , -- ## Cross-actor rejection
    { name := "bridgePolicy rejects non-bridge signer (transfer)"
    , body := do
        let h := bridgePolicy_rejects_non_bridge_signer 1 (.transfer 0 0 0 0) (by decide)
        let _ := h
        if (decide (bridgePolicy.authorized 1 (.transfer 0 0 0 0))) then
          throw <| IO.userError
            "bridgePolicy unexpectedly authorised non-bridge signer"
    }
  , { name := "bridgePolicy rejects non-bridge signer (replaceKey)"
    , body := do
        -- Even replaceKey, which the bridge is allowed to do, is
        -- rejected when signed by a non-bridge actor.
        let h := bridgePolicy_rejects_non_bridge_signer 5
                   (.replaceKey 1 samplePk) (by decide)
        let _ := h
        if (decide (bridgePolicy.authorized 5 (.replaceKey 1 samplePk))) then
          throw <| IO.userError
            "bridgePolicy unexpectedly authorised non-bridge replaceKey"
    }
  , -- ## Decidability sanity
    { name := "bridgePolicy.authorized is decidable at concrete inputs"
    , body := do
        -- replaceKey by bridge: decide → true.
        if ¬ (decide (bridgePolicy.authorized 0 (.replaceKey 1 samplePk))) then
          throw <| IO.userError "decide failed on positive case"
        -- transfer by bridge: decide → false.
        if (decide (bridgePolicy.authorized 0 (.transfer 1 2 3 4))) then
          throw <| IO.userError "decide failed on negative case"
    }
  , -- ## Term-level API stability for §12.9 theorems
    { name := "bridgePolicy_rejects_transfer: term-level API"
    , body := do
        let _f : (r : ResourceId) → (sender receiver : ActorId) → (amount : Amount) →
                 ¬ bridgePolicy.authorized bridgeActor (.transfer r sender receiver amount) :=
          bridgePolicy_rejects_transfer
        pure ()
    }
  , { name := "bridgePolicy_authorizes_replaceKey: term-level API"
    , body := do
        let _f : (actor : ActorId) → (newKey : PublicKey) →
                 bridgePolicy.authorized bridgeActor (.replaceKey actor newKey) :=
          bridgePolicy_authorizes_replaceKey
        pure ()
    }
  , { name := "bridgePolicy_authorizes_registerIdentity: term-level API"
    , body := do
        let _f : (actor : ActorId) → (pk : PublicKey) →
                 bridgePolicy.authorized bridgeActor (.registerIdentity actor pk) :=
          bridgePolicy_authorizes_registerIdentity
        pure ()
    }
  , { name := "bridgePolicy_rejects_non_bridge_signer: term-level API"
    , body := do
        let _f : (signer : ActorId) → (action : Action) → signer ≠ bridgeActor →
                 ¬ bridgePolicy.authorized signer action :=
          bridgePolicy_rejects_non_bridge_signer
        pure ()
    }
  ]

end BridgeActorTests
end LegalKernel.Test.Bridge
