\begin{code}
module TcTerm where

import BasicTypes
import Data.IORef
import TcMonad
import Data.List( (\\) )
import Text.PrettyPrint.HughesPJ

------------------------------------------
--      The top-level wrapper           --
------------------------------------------

typecheck :: Term -> Tc Sigma
typecheck e = do { ty <- inferSigma e
                 ; zonkType ty }

-----------------------------------
--      The expected type       --
-----------------------------------

data Expected a = Infer (IORef a) | Check a


------------------------------------------
--      tcRho, and its variants         --
------------------------------------------

-- checkRho takes the expected type as an argument
checkRho :: Term -> Rho -> Tc ()
-- Invariant: the Rho is always in weak-prenex form
checkRho expr ty = tcRho expr (Check ty)

inferRho :: Term -> Tc Rho
inferRho expr
  = do { ref <- newTcRef (error "inferRho: empty result")
       ; tcRho expr (Infer ref)
       ; readTcRef ref }

tcRho :: Term -> Expected Rho -> Tc ()
-- Invariant: if the second argument is (Check rho),
--            then rho is in weak-prenex form
tcRho (Lit _) exp_ty
  = instSigma intType exp_ty

-- Rule INST
-- When we reach a Var, look it up in the environment (fails if not in scope),
-- then instantiate its type w/ fresh meta type variables
-- then check if the resulting type is compatible w/ the expected type `exp_ty`
tcRho (Var v) exp_ty
  = do { v_sigma <- lookupVar v
       ; instSigma v_sigma exp_ty }

-- Infer the type of the function,
-- then type-check the argument by passing in the 
-- expected type of the argument (derived from the function),
-- then unify the function's result type w/ the expected result type
tcRho (App fun arg) exp_ty
  = do { fun_ty <- inferRho fun
       ; (arg_ty, res_ty) <- unifyFun fun_ty
       ; checkSigma arg arg_ty
       ; instSigma res_ty exp_ty }

-- (Rule ABS)
-- Split the expected type into the type of the bound variables & the type of the body
-- Then, extend the environment w/ a new binding & check the body 
tcRho (Lam var body) (Check exp_ty)
  = do { (var_ty, body_ty) <- unifyFun exp_ty
       ; extendVarEnv var var_ty (checkRho body body_ty) }

tcRho (Lam var body) (Infer ref)
  = do { var_ty  <- newTyVarTy
       ; body_ty <- extendVarEnv var var_ty (inferRho body)
       ; writeTcRef ref (var_ty --> body_ty) }

tcRho (ALam var var_ty body) (Check exp_ty)
  = do { (arg_ty, body_ty) <- unifyFun exp_ty
       ; subsCheck arg_ty var_ty
       ; extendVarEnv var var_ty (checkRho body body_ty) }

tcRho (ALam var var_ty body) (Infer ref)
  = do { body_ty <- extendVarEnv var var_ty (inferRho body)
       ; writeTcRef ref (var_ty --> body_ty) }

-- Type LET (let bindings)
-- Use inferSigma to infer the (polymorphic) type f rhs
tcRho (Let var rhs body) exp_ty
  = do { var_ty <- inferSigma rhs
       ; extendVarEnv var var_ty (tcRho body exp_ty) }

-- Handle type-annotated expressions
tcRho (Ann body ann_ty) exp_ty
   = do { checkSigma body ann_ty
        ; instSigma ann_ty exp_ty }


------------------------------------------
--      inferSigma and checkSigma
------------------------------------------

-- Implements the |-^{poly} judgement
-- getEnvTypes returns a list of all types in the environment Gamma
-- getMetaTyVars finds the free meta type variables in a list of types
-- Then, quantify over the list-difference of env_tvs & res_tvs
inferSigma :: Term -> Tc Sigma
inferSigma e
   = do { exp_ty <- inferRho e
        ; env_tys <- getEnvTypes
        ; env_tvs <- getMetaTyVars env_tys
        ; res_tvs <- getMetaTyVars [exp_ty]
        ; let forall_tvs = res_tvs \\ env_tvs
        ; quantify forall_tvs exp_ty }

checkSigma :: Term -> Sigma -> Tc ()
checkSigma expr sigma
  = do { (skol_tvs, rho) <- skolemise sigma
       ; checkRho expr rho
       ; env_tys <- getEnvTypes
       ; esc_tvs <- getFreeTyVars (sigma : env_tys)
       ; let bad_tvs = filter (`elem` esc_tvs) skol_tvs
       ; check (null bad_tvs)
               (text "Type not polymorphic enough") }

------------------------------------------
--      Subsumption checking            --
------------------------------------------

-- Implements the |-^{sh} judgement
-- `subsCheck args off exp` checks that
-- `off` is at least as polymorphic as `args -> exp`
subsCheck :: Sigma -> Sigma -> Tc ()

-- Here, skolemise performs the alpha-renaming of sigma2 & 
-- returns fresh concrete ype 
subsCheck sigma1 sigma2        -- Rule DEEP-SKOL
  = do { (skol_tvs, rho2) <- skolemise sigma2
       ; subsCheckRho sigma1 rho2
       ; esc_tvs <- getFreeTyVars [sigma1,sigma2]
       -- Ensure that the skolemised variables aren't free
       ; let bad_tvs = filter (`elem` esc_tvs) skol_tvs
       ; check (null bad_tvs)
               (vcat [text "Subsumption check failed:",
                      nest 2 (ppr sigma1),
                      text "is not as polymorphic as",
                      nest 2 (ppr sigma2)])
    }

subsCheckRho :: Sigma -> Rho -> Tc ()
-- Invariant: the second argument is in weak-prenex form

subsCheckRho sigma1@(ForAll _ _) rho2    -- Rule SPEC
  = do { rho1 <- instantiate sigma1
       ; subsCheckRho rho1 rho2 }

subsCheckRho rho1 (Fun a2 r2)            -- Rule FUN
  = do { (a1,r1) <- unifyFun rho1; subsCheckFun a1 r1 a2 r2 }

subsCheckRho (Fun a1 r1) rho2            -- Rule FUN
  = do { (a2,r2) <- unifyFun rho2; subsCheckFun a1 r1 a2 r2 }

subsCheckRho tau1 tau2                   -- Rule MONO
  = unify tau1 tau2    -- Revert to ordinary unification

subsCheckFun :: Sigma -> Rho -> Sigma -> Rho -> Tc ()
subsCheckFun a1 r1 a2 r2
  = do { subsCheck a2 a1 ; subsCheckRho r1 r2 }

-- Implements the judgement |-^{inst}
instSigma :: Sigma -> Expected Rho -> Tc ()
-- Invariant: if the second argument is (Check rho),
--            then rho is in weak-prenex form
instSigma t1 (Check t2) = subsCheckRho t1 t2
instSigma t1 (Infer r)  = do { t1' <- instantiate t1
                             ; writeTcRef r t1' }
\end{code}
