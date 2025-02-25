import Std.Data.BinomialHeap
import Duper.ProverM
import Duper.Util.Iterate
import Duper.RuleM
import Duper.MClause
import Duper.Simp
import Duper.Rules.ClauseSubsumption
import Duper.Rules.Clausification
import Duper.Rules.ClausifyPropEq
import Duper.Rules.Demodulation
import Duper.Rules.ElimDupLit
import Duper.Rules.ElimResolvedLit
import Duper.Rules.EqualityFactoring
import Duper.Rules.EqualityResolution
import Duper.Rules.EqualitySubsumption
import Duper.Rules.IdentBoolFalseElim
import Duper.Rules.IdentPropFalseElim
import Duper.Rules.SimplifyReflect
import Duper.Rules.Superposition
import Duper.Rules.SyntacticTautologyDeletion1
import Duper.Rules.SyntacticTautologyDeletion2
import Duper.Rules.SyntacticTautologyDeletion3
import Duper.Rules.DestructiveEqualityResolution
-- Higher order rules
import Duper.Rules.ArgumentCongruence
import Duper.Rules.BoolHoist

namespace Duper

namespace ProverM
open Lean
open Meta
open Lean.Core
open Result
open Std
open ProverM
open RuleM

initialize
  registerTraceClass `Simp
  registerTraceClass `Simp.debug
  registerTraceClass `Timeout.debug

open SimpResult

def forwardSimpRules : ProverM (Array SimpRule) := do
  return #[
    clausificationStep.toSimpRule,
    syntacticTautologyDeletion1.toSimpRule,
    syntacticTautologyDeletion2.toSimpRule,
    syntacticTautologyDeletion3.toSimpRule,
    elimDupLit.toSimpRule,
    elimResolvedLit.toSimpRule,
    destructiveEqualityResolution.toSimpRule,
    identPropFalseElim.toSimpRule,
    identBoolFalseElim.toSimpRule,
    (forwardDemodulation (← getDemodSidePremiseIdx)).toSimpRule,
    (forwardClauseSubsumption (← getSubsumptionTrie)).toSimpRule,
    (forwardEqualitySubsumption (← getSubsumptionTrie)).toSimpRule,
    -- (forwardPositiveSimplifyReflect (← getSubsumptionTrie)).toSimpRule
    -- TODO: Forward negative simplify reflect
    -- Higher order rules
    boolHoist.toSimpRule -- Temporarily disabling this because it's causing unknown metavariable errors
  ]

def backwardSimpRules : ProverM (Array BackwardSimpRule) := do
  return #[
    (backwardDemodulation (← getMainPremiseIdx)).toBackwardSimpRule,
    (backwardClauseSubsumption (← getSubsumptionTrie)).toBackwardSimpRule,
    (backwardEqualitySubsumption (← getSubsumptionTrie)).toBackwardSimpRule
    -- (backwardPositiveSimplifyReflect (← getSubsumptionTrie)).toBackwardSimpRule
    -- TODO: Backward negative simplify reflect
  ]

def applyForwardSimpRules (givenClause : Clause) : ProverM (SimpResult Clause) := do
  for simpRule in ← forwardSimpRules do
    match ← simpRule givenClause with
    | Removed => return Removed
    | Applied c => return Applied c
    | Unapplicable => continue
  return Unapplicable

partial def forwardSimpLoop (givenClause : Clause) : ProverM (Option Clause) := do
  Core.checkMaxHeartbeats "forwardSimpLoop"
  let activeSet ← getActiveSet
  match ← applyForwardSimpRules givenClause with
  | Applied c =>
    if activeSet.contains c then return none
    else forwardSimpLoop c
  | Unapplicable => return some givenClause 
  | Removed => return none

/-- Uses other clauses in the active set to attempt to simplify the given clause. Returns some simplifiedGivenClause if
    forwardSimpLoop is able to use simplification rules to transform givenClause to simplifiedGivenClause. Returns none if
    forwardSimpLoop is able to use simplification rules to show that givenClause is unneeded. -/
def forwardSimplify (givenClause : Clause) : ProverM (Option Clause) := do
  let c := forwardSimpLoop givenClause
  c

/-- Attempts to use givenClause to apply backwards simplification rules (starting from the startIdx's backward simplification rule) on clauses
    in the active set. -/
def applyBackwardSimpRules (givenClause : Clause) : ProverM Unit := do
  let backwardSimpRules ← backwardSimpRules
  for i in [0 : backwardSimpRules.size] do
    let simpRule := backwardSimpRules[i]!
    simpRule givenClause

/-- Uses the givenClause to attempt to simplify other clauses in the active set. For each clause that backwardSimplify is
    able to produce a simplification for, backwardSimplify removes the clause adds any newly simplified clauses to the passive set.
    Additionally, for each clause removed from the active set in this way, all descendents of said clause should also be removed from
    the current state's allClauses and passiveSet -/
def backwardSimplify (givenClause : Clause) : ProverM Unit := applyBackwardSimpRules givenClause

def performInferences (givenClause : Clause) : ProverM Unit := do
  performEqualityResolution givenClause
  performClausifyPropEq givenClause
  performSuperposition givenClause
  performEqualityFactoring givenClause
  -- Higher order rules
  performArgCong givenClause

partial def saturate : ProverM Unit := do
  Core.withCurrHeartbeats $ iterate $
    try do
      Core.checkMaxHeartbeats "saturate"
      let some givenClause ← chooseGivenClause
        | do
          setResult saturated
          return LoopCtrl.abort
      trace[Prover.saturate] "Given clause: {givenClause}"
      let some simplifiedGivenClause ← forwardSimplify givenClause
        | return LoopCtrl.next
      trace[Prover.saturate] "Given clause after simp: {simplifiedGivenClause}"
      backwardSimplify simplifiedGivenClause
      addToActive simplifiedGivenClause
      performInferences simplifiedGivenClause
      trace[Prover.saturate] "New active Set: {(← getActiveSet).toArray}"
      return LoopCtrl.next
    catch
    | Exception.internal emptyClauseExceptionId _  =>
      setResult ProverM.Result.contradiction
      return LoopCtrl.abort
    | e =>
      trace[Timeout.debug] "Active set at timeout: {(← getActiveSet).toArray}"
      --trace[Timeout.debug] "All clauses at timeout: {Array.map (fun x => x.1) (← getAllClauses).toArray}"
      throw e

end ProverM

end Duper
