import Duper.MClause
import Duper.RuleM

namespace Duper
open RuleM
open Lean

-- TODO: Add simplification to always put True/False on right-hand side?
def getSelections (c : MClause) : List Nat := Id.run do
  -- simply select first negative literal:
  for i in [:c.lits.size] do
    if c.lits[i].sign == false ∨ c.lits[i].rhs == mkConst ``False then
      return [i]
  return []

def litSelectedOrNothingSelected (c : MClause) (i : Nat) :=
  let sel := getSelections c
  if sel == []
  then true
  else sel.contains i

def litSelected (c : MClause) (i : Nat) :=
  let sel := getSelections c
  sel.contains i

/-- A literal l (with index i) from clause c is eligible for paramodulation if:
  1. l is a positive literal (l.sign = true)
  2. The set of selections for clasue c is empty
  3. l is maximal in c
-/
def eligibleForParamodulation (c : MClause) (i : Nat) : RuleM Bool := do
  let constraint1 := c.lits[i].sign
  let constraint2 := getSelections c == List.nil
  let constraint3 := ← runMetaAsRuleM $ c.isMaximalLit (← getOrder) i
  return constraint1 && constraint2 && constraint3

end Duper