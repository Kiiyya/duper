import Duper.Clause

namespace Duper
open Lean

structure MClause :=
(lits : Array Lit)
deriving Inhabited, BEq, Hashable

namespace MClause

def toExpr (c : MClause) : Expr :=
  litsToExpr c.lits.data
where litsToExpr : List Lit → Expr
| [] => mkConst ``False
| [l] => l.toExpr
| l :: ls => mkApp2 (mkConst ``Or) l.toExpr (litsToExpr ls)

def fromExpr (e : Expr) : MClause :=
  MClause.mk (litsFromExpr e).toArray
where   litsFromExpr : Expr → List Lit
| .app (.app (.const ``Or _) litexpr) other => Lit.fromExpr litexpr :: litsFromExpr other
| .const ``False _                            => []
| e@(_)                                       => [Lit.fromExpr e]

def appendLits (c : MClause) (lits : Array Lit) : MClause :=
  ⟨c.lits.append lits⟩

def eraseLit (c : MClause) (idx : Nat) : MClause :=
  ⟨c.lits.eraseIdx idx⟩

def replaceLit? (c : MClause) (idx : Nat) (l : Lit) : Option MClause :=
  if idx >= c.lits.size then
    none
  else
    some ⟨c.lits.set! idx l⟩

def replaceLit! (c : MClause) (idx : Nat) (l : Lit) : MClause :=
  ⟨c.lits.set! idx l⟩

def mapM {m : Type → Type w} [Monad m] (f : Expr → m Expr) (c : MClause) : m MClause := do
  return ⟨← c.lits.mapM (fun l => l.mapM f)⟩

def fold {β : Type v} (f : β → Expr → β) (init : β) (c : MClause) : β := Id.run $ do
  let mut acc := init
  for i in [:c.lits.size] do
    let f' := fun acc e => f acc e
    acc := c.lits[i]!.fold f' acc
  return acc

def foldM {β : Type v} {m : Type v → Type w} [Monad m] 
    (f : β → Expr → ClausePos → m β) (init : β) (c : MClause) : m β := do
  let mut acc := init
  for i in [:c.lits.size] do
    let f' := fun acc e pos => f acc e ⟨i, pos.side, pos.pos⟩
    acc ← c.lits[i]!.foldM f' acc
  return acc

def foldGreenM {β : Type v} {m : Type v → Type w} [Monad m] 
    (f : β → Expr → ClausePos → m β) (init : β) (c : MClause) : m β := do
  let mut acc := init
  for i in [:c.lits.size] do
    let f' := fun acc e pos => f acc e ⟨i, pos.side, pos.pos⟩
    acc ← c.lits[i]!.foldGreenM f' acc
  return acc

def getAtPos! (c : MClause) (pos : ClausePos) : Expr :=
  c.lits[pos.lit]!.getAtPos! ⟨pos.side, pos.pos⟩

def replaceAtPos? (c : MClause) (pos : ClausePos) (replacement : Expr) : Option MClause :=
  if (pos.lit ≥ c.lits.size) then none
  else
    let litPos : LitPos := {side := pos.side, pos := pos.pos}
    match c.lits[pos.lit]!.replaceAtPos? litPos replacement with
    | some newLit => some {lits := Array.set! c.lits pos.lit newLit}
    | none => none

def replaceAtPos! (c : MClause) (pos : ClausePos) (replacement : Expr) [Monad m] [MonadError m] : m MClause :=
  let litPos : LitPos := {side := pos.side, pos := pos.pos}
  return {lits := Array.set! c.lits pos.lit $ ← c.lits[pos.lit]!.replaceAtPos! litPos replacement}

/-- This function acts as Meta.kabstract except that it takes a ClausePos rather than Occurrences and expects
    the given expression to consist only of applications up to the given ExprPos. Additionally, since the exact
    position is given, we don't need to pass in Meta.kabstract's second argument p -/
def abstractAtPos! (c : MClause) (pos : ClausePos) : MetaM MClause := do
  let litPos : LitPos := {side := pos.side, pos := pos.pos}
  return {lits := Array.set! c.lits pos.lit $ ← c.lits[pos.lit]!.abstractAtPos! litPos}

def append (c : MClause) (d : MClause) : MClause := ⟨c.lits.append d.lits⟩

def eraseIdx (i : Nat) (c : MClause) : MClause := ⟨c.lits.eraseIdx i⟩

def isTrivial (c : MClause) : Bool := Id.run do
  -- TODO: Also check if it contains the same literal positively and negatively?
  for lit in c.lits do
    if lit.sign ∧ lit.lhs == lit.rhs then
      return true
  return false

open Comparison
def isMaximalLit (ord : Expr → Expr → MetaM Comparison) (c : MClause) (idx : Nat) (strict := false) : MetaM Bool := do
  for j in [:c.lits.size] do
    if j == idx then continue
    let c ← Lit.compare ord c.lits[idx]! c.lits[j]!
    if c == GreaterThan || (not strict && c == Equal) || c == Incomparable
      then continue
    else return false
  return true

/-- Returns true if there may be some assignment in which the given idx is maximal, and false if there is some idx' that is strictly greater
    than idx (in this case, since idx < idx', for any subsitution σ, idx σ < idx' σ so idx can never be maximal)

    Note that for this function, strictness does not actually matter, because regardless of whether we are considering potential strict maximality
    or potential nonstrict maximality, we can only determine that idx can never be maximal if we find an idx' that is strictly gerater than it
-/
def canNeverBeMaximal (ord : Expr → Expr → MetaM Comparison) (c : MClause) (idx : Nat) : MetaM Bool := do
  for j in [:c.lits.size] do
    if j != idx && (← Lit.compare ord c.lits[idx]! c.lits[j]!) == LessThan then
      return true
    else continue
  return false

end MClause
end Duper