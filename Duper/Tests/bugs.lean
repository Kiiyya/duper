import Duper.TPTP
import Duper.Tactic

set_option maxHeartbeats 20000

tptp PUZ137_8 "../TPTP-v8.0.0/Problems/PUZ/PUZ137_8.p"
  by duper -- Prover saturated (from PUZ_tests.lean)

tptp PUZ031_1_modified "../TPTP-v8.0.0/Problems/PUZ/PUZ031_1.p" by 
  have inhabited_plant : Inhabited plant := sorry
  have inhabited_snail : Inhabited snail := sorry
  have inhabited_grain : Inhabited grain := sorry
  have inhabited_bird : Inhabited bird := sorry
  have inhabited_fox : Inhabited fox := sorry
  have inhabited_wolf : Inhabited wolf := sorry
  duper
  -- If these instances are not provided, duper will fail
  -- Previously: Error when reconstructing clausification

tptp COM035_5 "../TPTP-v8.0.0/Problems/COM/COM025_5.p"
  by duper


example (x : Type u) (f g : Type u → Type v) (H : f = g) : f x = g x :=
  by duper
-- Previously: Type mismatch caused by incorrect manipulation of
-- universe levels in `ArgCong`

set_option trace.Meta.debug true in
example (f : Prop → Nat) :
  f (∀ (x : Nat), x ≠ Nat.zero) = f False := by duper

set_option trace.Meta.debug true in
example (f : Prop → Nat) :
  f (f (∀ (x : Nat), x ≠ Nat.zero) = f False) = f True := by duper

set_option trace.Meta.debug true in
example (f g : Nat → Nat) (h : ∀ a, ∃ d, f a = d) :
  ∀ a, ∃ d, f a = d := by duper

set_option trace.Print_Proof true in
example : ((∀ (f : Nat → Nat) (x : Nat), f x = f x) = True) := by duper

set_option trace.Meta.debug true in
example : ((∀ (A : Type) (f : Nat → A) (x : Nat), f x = f x) = True) := by duper

set_option trace.Print_Proof true in
example : ((∃ (A B : Type) (f : B → A) (x : B), f x = f x) = True) :=
  by duper

set_option trace.Print_Proof true in
example : ∃ (A : Type) (B : A → Type) (f : ∀ (a : A), B a) (x : A), (f x = f x) = True :=
  by duper

example (A : Type) (x : A) : (∃ x : A, x = x) := by duper