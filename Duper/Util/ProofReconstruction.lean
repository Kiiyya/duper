import Duper.ProverM
import Duper.RuleM
import Duper.MClause
import Duper.Util.Misc

namespace Duper
open RuleM
open Lean

initialize Lean.registerTraceClass `InstantiatePremises

-- `xs` is usually obtained by `Meta.forallTelescope c.toForallExpr fun xs body =>`
def instantiatePremises (parents : List ProofParent) (premises : List Expr) (xs : Array Expr) : 
    MetaM (List (Array Lit) × List Expr) := do
  let mut parentsLits := [] -- Initializing with capacity 2 because most inference and simplification rules have at most two parents
  let mut appliedPremises := []
  for (parent, premise) in List.zip parents premises do
    let finstantiatedparent_pre ← parent.expr.instantiateForallNoReducing xs
    -- `fvars = xs ++ vanishedvars`
    -- `finstantiatedparent = ((.mdata) fun [vars] => parent[vars]) mvars[fvars]`
    let (mvars, bis, finstantiatedparent) ← Meta.forallMetaTelescope finstantiatedparent_pre
    for m in mvars do
      let ty ← Meta.inferType m
      let id := m.mvarId!
      id.assign (← Meta.findInstance ty)
    -- `parentInstantiations = mvars[fvars]`
    let parentInstantiations := finstantiatedparent.getAppArgs
    trace[InstantiatePremises] "parentInstantiations: {parentInstantiations}"
    parentsLits := parent.clause.lits.map (fun lit => lit.map (fun e => e.instantiateRev parentInstantiations)) :: parentsLits
    appliedPremises := mkAppN premise parentInstantiations :: appliedPremises
    -- Now, `appliedPremises[i] : parentsLits[i]`, for all `i`
  return (parentsLits, appliedPremises)

/-- Construct a proof of `lits[0] ∨ ... ∨ lits[n] → target`, given proofs (`casesProofs`) of `lits[i] → target` -/
def orCases (lits : Array Expr) (caseProofs : Array Expr) : MetaM Expr := do
  let mut ors := #[lits[lits.size - 1]!]
  for l in [2:lits.size+1] do
    ors := ors.push (mkApp2 (mkConst ``Or) lits[lits.size - l]! ors[ors.size-1]!)
  let mut r := caseProofs[caseProofs.size - 1]!
  for k in [2:caseProofs.size+1] do
    let newOne := caseProofs[caseProofs.size - k]!
    r ← Meta.withLocalDeclD `h ors[k-1]! fun h => do
      let p ← Meta.mkAppM ``Or.elim #[h, newOne, r]
      Meta.mkLambdaFVars #[h] p
  return r

/-- Construct a proof of `lits[0] ∨ ... ∨ lits[n]`, given a `proof` of `lits[i]` -/
def orIntro (lits : Array Expr) (i : Nat) (proof : Expr) : MetaM Expr := do
  let mut tyR := lits[lits.size-1]!
  for j in [2:lits.size-i] do
    tyR := mkApp2 (mkConst ``Or) lits[lits.size - j]! tyR
  let mut proofRight :=
    if i != lits.size - 1 then
      mkApp3 (mkConst ``Or.inl) lits[i]! tyR proof
    else
      proof
  if i != lits.size - 1 then
    tyR := mkApp2 (mkConst ``Or) lits[i]! tyR
  for j in [lits.size-i+1:lits.size+1] do
    proofRight := mkApp3 (mkConst ``Or.inr) lits[lits.size-j]! tyR proofRight
    tyR := mkApp2 (mkConst ``Or) lits[lits.size-j]! tyR
  return proofRight

/-- Construct a proof of `lits[0] ∨ ... ∨ lits[n]`, given a `proof` of the subclause consisting of the last `i` literals -/
def orSubclause (lits : Array Expr) (i : Nat) (proof : Expr) : MetaM Expr := do
  let mut tyR := lits[lits.size - 1]!
  for j in [2:i+1] do
    tyR := mkApp2 (mkConst ``Or) lits[lits.size - j]! tyR
  let mut proofRight := proof -- proof is a proof of the last `i` literals, which is currently the subclause contained by tyR
  for j in [i+1:lits.size+1] do
    proofRight := mkApp3 (mkConst ``Or.inr) lits[lits.size-j]! tyR proofRight
    tyR := mkApp2 (mkConst ``Or) lits[lits.size-j]! tyR
  return proofRight

end Duper