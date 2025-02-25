import Duper.Simp
import Duper.Selection
import Duper.Util.ProofReconstruction
import Duper.ProverM

namespace Duper

open Lean
open RuleM
open SimpResult
open ProverM
open Std
initialize Lean.registerTraceClass `Rule.clauseSubsumption

/-- Determines whether there is any σ such that σ(l1.lhs) = l2.lhs and σ(l1.rhs) = l2.rhs. Returns true and applies σ if so,
    returns false (without applying any substitution) otherwise -/
def checkDirectMatch (l1 : Lit) (l2 : Lit) (protectedMVarIds : Array MVarId) : RuleM Bool :=
  performMatch #[(l2.lhs, l1.lhs), (l2.rhs, l1.rhs)] protectedMVarIds -- l2 is first argument in each pair so only l1's mvars can receive assignments

/-- Determines whether there is any σ such that σ(l1.rhs) = l2.lhs and σ(l1.lhs) = l2.rhs. Returns true and applies σ if so,
    returns false (without applying any substitution) otherwise -/
def checkCrossMatch (l1 : Lit) (l2 : Lit) (protectedMVarIds : Array MVarId) : RuleM Bool :=
  performMatch #[(l2.lhs, l1.rhs), (l2.rhs, l1.lhs)] protectedMVarIds -- l2 is first argument in each pair so only l1's mvars can receive assignments

/-- Determines whether σ(l1) = l2 for any substitution σ. Importantly, litsMatch can return true if l1.sign = l2.sign and either:
    - σ(l1.lhs) = l2.lhs and σ(l1.rhs) = l2.rhs
    - σ(l1.rhs) = l2.lhs and σ(l1.lhs) = l2.rhs -/
def litsMatch (l1 : Lit) (l2 : Lit) (protectedMVarIds : Array MVarId) : RuleM Bool := do
  if l1.sign != l2.sign then return false
  else if ← checkDirectMatch l1 l2 protectedMVarIds then return true
  else if ← checkCrossMatch l1 l2 protectedMVarIds then return true
  else return false

/-- Determines whether, for any substitution σ, σ(l) is in c at startIdx or after startIdx. If it is, then metavariables are assigned so that σ is
    applied and the index of σ(l) in c is returned. If there are multiple indices in c that l can match, then litInClause returns the first one.
    If there is no substitution σ such that σ(l) is in c at or after startIdx, the MetavarContext is left unchanged and none is returned.

    Additionally, litInClause is not allowed to return any Nat that is part of the exclude set. This is to prevent instances in which multiple
    literals in the subsumingClause all map onto the same literal in the subsumedClause. -/
def litInClause (l : Lit) (c : MClause) (cMVarIds : Array MVarId) (exclude : HashSet Nat) (startIdx : Nat) : RuleM (Option Nat) := do
  for i in [startIdx:c.lits.size] do
    if exclude.contains i then
      continue
    else
      let cLit := c.lits[i]!
      if ← litsMatch l cLit cMVarIds then return some i
      else continue
  return none

/-- Attempts to find an injective mapping f from subsumingClauseLits to subsumedClauseLits and a substitution σ such that
    for every literal l ∈ subsumingClauseLits, σ(l) = f(l). If subsumptionCheckHelper fails to find such a mapping and substitution,
    then subsumptionCheckHelper returns none without modifying the state's MetavarContext.

    If subsumptionCheckHelper succeeds, then it assigns MVars to apply σ and returns a list of nats res such that:
    ∀ i ∈ [0, subsumingClauseLits.length], σ(subsumingClauseLits.get! i) = subsumedClauseLits[res.get! i]

    The argument exclude contains a set of Nats that cannot be mapped to (so that injectivity is preserved). The argument fstStart is provided
    to facilitate backtracking.
    
    subsumptionCheckHelper is defined as a partialDef, but should always terminate because every recursive call either makes subsumingClauseLits
    smaller or makes fstStart bigger (and once fstStart exceeds the size of subsumedClauseLits.lits, litInClause is certain to fail) -/
partial def subsumptionCheckHelper (subsumingClauseLits : List Lit) (subsumedClauseLits : MClause) (subsumedClauseMVarIds : Array MVarId)
  (exclude : HashSet Nat) (fstStart := 0) : RuleM Bool := do
  match subsumingClauseLits with
  | List.nil => return true
  | l :: restSubsumingClauseLits =>
    match ← litInClause l subsumedClauseLits subsumedClauseMVarIds exclude fstStart with
    | none => return false
    | some idx =>
      let tryWithIdx ←
        conditionallyModifyingMCtx do -- Only modify the MCtx if the recursive call succeeds
          let exclude := exclude.insert idx
          if ← subsumptionCheckHelper restSubsumingClauseLits subsumedClauseLits subsumedClauseMVarIds exclude then return (true, true)
          else return (false, false)
      /- tryWithIdx indicates whether it is possible to find an injective mapping from subsumingClauseLits to subsumedClauseLits that satisfies
         the constraints of subsumption where the first literal in subsumingClauseLits is mapped to the first possible literal in subsumingClauseLits
         after fstStart. If tryWithIdx succeeded, then we can simply return that success and have no need to backtrack. But if tryWithIdx failed,
         then matching l with the first lit possible after fstStart in subsumedClauseLits doesn't work. Therefore, we should simulate backtracking
         to that decision by recursing with fstStart one above idx -/
      if tryWithIdx then return true
      else subsumptionCheckHelper subsumingClauseLits subsumedClauseLits subsumedClauseMVarIds exclude (idx + 1)

def subsumptionCheck (subsumingClause : MClause) (subsumedClause : MClause) (subsumedClauseMVarIds : Array MVarId) : RuleM Bool :=
  conditionallyModifyingMCtx do -- Only modify the MCtx if the subsumption check succeeds (so failed checks don't impact future checks)
    if subsumingClause.lits.size > subsumedClause.lits.size then return (false, false)
    if ← subsumptionCheckHelper (subsumingClause.lits).toList subsumedClause subsumedClauseMVarIds {} then return (true, true)
    else return (false, false)

/-- Returns true if there exists a clause that subsumes c, and returns false otherwise -/
def forwardClauseSubsumption (subsumptionTrie : SubsumptionTrie) : MSimpRule := fun c => do
  let potentialSubsumingClauses ← subsumptionTrie.getPotentialSubsumingClauses c
  trace[Rule.clauseSubsumption] "number of potentialSubsumingClauses for {c}: {potentialSubsumingClauses.size}"
  let (cMVars, c) ← loadClauseCore c
  let cMVarIds := cMVars.map Expr.mvarId!
  let fold_fn := fun acc nextClause => do
    match acc with
    | false =>
      conditionallyModifyingLoadedClauses do
        let nextClause ← loadClause nextClause
        if ← subsumptionCheck nextClause c cMVarIds then
          trace[Rule.clauseSubsumption] "Forward subsumption: removed {c.lits} because it was subsumed by {nextClause.lits}"
          return (true, true)
        else return (false, false)
    | true => return true
  potentialSubsumingClauses.foldlM fold_fn false

/-- Returns the list of clauses that givenSubsumingClause subsumes -/
def backwardClauseSubsumption (subsumptionTrie : SubsumptionTrie) : BackwardMSimpRule := fun givenSubsumingClause => do
  let potentialSubsumedClauses ← subsumptionTrie.getPotentialSubsumedClauses givenSubsumingClause
  trace[Rule.clauseSubsumption] "number potentialSubsumedClauses for {givenSubsumingClause}: {potentialSubsumedClauses.size}"
  let givenSubsumingClause ← loadClause givenSubsumingClause
  let fold_fn := fun acc nextClause =>
    conditionallyModifyingLoadedClauses do
      let (nextClauseMVars, nextClauseM) ← loadClauseCore nextClause
      let nextClauseMVarIds := nextClauseMVars.map Expr.mvarId!
      if ← subsumptionCheck givenSubsumingClause nextClauseM nextClauseMVarIds then
        trace[Rule.clauseSubsumption] "Backward subsumption: removed {nextClause.lits} because it was subsumed by {givenSubsumingClause.lits}"
        return (true, (nextClause :: acc))
      else return (false, acc)
  potentialSubsumedClauses.foldlM fold_fn []