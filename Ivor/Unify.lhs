> {-# OPTIONS_GHC -fglasgow-exts #-}

> module Ivor.Unify where

> import Ivor.Nobby
> import Ivor.TTCore
> import Ivor.Errors
> import Ivor.Evaluator
> import Ivor.Values

> import Data.List

> import Debug.Trace

> type Unified = [(Name, TT Name)]

> type Subst = Name -> TT Name

Unify on named terms, but normalise using de Bruijn indices.
(I hope this doesn't get too confusing...)

> unify :: Gamma Name -> Indexed Name -> Indexed Name -> IvorM Unified
> unify gam x y = unifyenv gam [] (finalise x) (finalise y)

> unifyenv :: Gamma Name -> Env Name ->
>             Indexed Name -> Indexed Name -> IvorM Unified
> unifyenv = unifyenvErr False

> unifyenvCollect :: Gamma Name -> Env Name ->
>                    Indexed Name -> Indexed Name -> IvorM Unified
> unifyenvCollect = unifyenvErr True

> unifyenvErr :: Bool -> -- Ignore errors
>                Gamma Name -> Env Name ->
>                Indexed Name -> Indexed Name -> IvorM Unified
> -- For the sake of readability of the results, first attempt to unify
> -- without reducing, and reduce if that doesn't work.
> -- Also, there is no point reducing if we don't have to, and not calling
> -- the normaliser really speeds things up if we have a lot of easy
> -- constraints to solve...
> unifyenvErr i gam env x y = {- trace ("Unifying " ++ (show (x,y) ++ "\n" ++
>                                    show (p (normalise (gam' gam) x)) ++ "\n" ++
>                                    show (p (normalise (gam' gam) x)))) $ -}
>     case unifynferr False env (p x)
>                               (p y) of
>           (Right x) -> return x

>           _ -> {- trace (dbgtt x ++ ", " ++ dbgtt y ++"\n") $ -}
>                unifynferr i env (p (eval_nf (gam' gam) x))
>                                 (p (eval_nf (gam' gam) y))

           _ -> unifynferr i env (p (normalise (gam' gam) x))
                                 (p (normalise (gam' gam) y))

>    where p (Ind t) = Ind t --(makePs t)
>          gam' g = concatGam g (envToGamHACK env)
>          dbgtt (Ind x) = show x -- debugTT x

Make the local environment something that Nobby knows about. Very hacky...

> envToGamHACK [] = emptyGam
> envToGamHACK ((n,B (Let v) ty):xs)
>     = insertGam n (G (Fun [] (Ind v)) (Ind ty) defplicit) (envToGamHACK xs)
> envToGamHACK (_:xs) = envToGamHACK xs

> unifynf :: Env Name -> Indexed Name -> Indexed Name -> IvorM Unified
> unifynf = unifynferr True

Collect names which do unify, and ignore errors

> unifyCollect :: Env Name -> Indexed Name -> Indexed Name -> IvorM Unified
> unifyCollect = unifynferr False

> sentinel = [(MN ("HACK!!",0), P (MN ("HACK!!",0)))]

> unifynferr :: Bool -> -- Ignore errors
>               Env Name -> Indexed Name -> Indexed Name -> IvorM Unified
> unifynferr ignore env topx@(Ind x) topy@(Ind y)
>                = do acc <- un env env x y []
>                     if ignore then return () else checkAcc acc
>                     return (acc \\ sentinel)
>    where un envl envr (P x) (P y) acc
>              | x == y = return acc
>              | loc x envl == loc y envr && loc x envl >=0
>                  = return acc
>              | hole envl x && hole envl y = return ((x, (P y)): acc)
>          un envl envr (Bind x (B Lambda ty) (Sc (App scl (P x')))) y acc
>                | x == x' = un envl envr scl y acc
>          un envl envr y (Bind x (B Lambda ty) (Sc (App scr (P x')))) acc
>                | x == x' = un envl envr y scr acc
>          un envl envr (Bind x (B Lambda ty) (Sc (App scl (V 0)))) y acc
>                = un envl envr y scl acc
>          un envl envr y (Bind x (B Lambda ty) (Sc (App scr (V 0)))) acc
>                = un envl envr y scr acc
>          un envl envr (P x) t acc | hole envl x = return ((x,t):acc)
>          un envl envr t (P x) acc | hole envl x = return ((x,t):acc)
>          un envl envr (Bind x b@(B Hole ty) (Sc sc)) t acc
>             = un ((x,b):envl) envr sc t acc
>          un envl envr (Bind x b (Sc sc)) (Bind x' b' (Sc sc')) acc =
>              do acc' <- unb envl envr b b' acc
>                 un ((x,b):envl) ((x',b'):envr) sc sc' acc'
>          un envl envr (Bind x b@(B (Let v) ty) (Sc sc)) t acc
>             = un ((x,b):envl) envr sc t acc
>          un envl envr t (Bind x b@(B (Let v) ty) (Sc sc)) acc
>             = un envl ((x,b):envr) t sc acc
>                 -- combine bu scu
>          un envl envr x@(App (P f) s) y@(App (P f') s') acc
>                     | x == y && not ignore = return acc
>                     | x /=y && not ignore = ifail $ ICantUnify (Ind x) (Ind y)
>          -- if unifying the functions fails because the names are different,
>          -- unifying the arguments is going to be a waste of time bec
>          un envl envr x@(App f s) y@(App f' s') acc
>              | funify (getFun f) (getFun f') = -- trace ("OK " ++ show (f,f',getFun f, getFun f')) $
>                   do acc' <- un envl envr f f' acc
>                      un envl envr s s' acc'
>              | otherwise = if ignore then return acc
>                               else ifail $ ICantUnify (Ind x) (Ind y)
>             where funify (P x) (P y)
>                       | x==y = True
>                       | otherwise = False -- hole envl x || hole envl y
>                   funify (Con _ _ _) (P x) = False -- hole envr x
>                   funify (P x) (Con _ _ _) = False -- hole envl x
>                   funify (TyCon _ _) (P x) = False -- hole envr x
>                   funify (P x) (TyCon _ _) = False -- hole envl x
>                   funify (P x) (App _ _) = False
>                   funify (App _ _) (P x) = False
>                   funify _ _ = True -- unify normally
>          un envl envr (Proj _ i t) (Proj _ i' t') acc
>             | i == i' = un envl envr t t' acc
>          un envl envr (Label t c) (Label t' c') acc = un envl envr t t' acc
>          un envl envr (Call c t) (Call c' t') acc = un envl envr t t' acc
>          un envl envr (Return t) (Return t') acc = un envl envr t t' acc
>          un envl envr (Stage x) (Stage y) acc = unst envl envr x y acc
>          un envl envr (Meta _ _) (Meta _ _) acc = return acc
>          un envl envr Erased _ acc = return acc
>          un envl envr _ Erased acc = return acc
>          un envl envr x y acc
>                     | x == y || ignore = return acc
>                     | otherwise = ifail $ ICantUnify (Ind x) (Ind y)
>          unb envl envr (B b ty) (B b' ty') acc =
>              do acc' <- unbb envl envr b b' acc
>                 un envl envr ty ty' acc'
>          unbb envl envr Lambda Lambda acc = return acc
>          unbb envl envr Pi Pi acc = return acc
>          unbb envl envr Hole Hole acc = return acc
>          unbb envl envr (Let v) (Let v') acc = un envl envr v v' acc
>          unbb envl envr (Guess v) (Guess v') acc = un envl envr v v' acc
>          unbb envl envr x y acc
>                   = if ignore then return acc
>                        else tacfail $ "Can't unify binders " ++ show x ++ " and " ++ show y

>          unst envl envr (Quote x) (Quote y) acc = un envl envr x y acc
>          unst envl envr (Code x) (Code y) acc = un envl envr x y acc
>          unst envl envr (Eval x _) (Eval y _) acc = un envl envr x y acc
>          unst envl envr (Escape x _) (Escape y _) acc = un envl envr x y acc
>          unst envl envr x y acc =
>                   if ignore then return acc
>                       else ifail $ ICantUnify (Ind (Stage x)) (Ind (Stage y))

>          hole env x | (Just (B Hole ty)) <- lookup x env = True
>                     | otherwise = isInferred x
>          isInferred (MN ("INFER",_)) = True -- OK, a bit of a nasty hack.
>          isInferred _ = False

>          checkAcc [] = return ()
>          checkAcc ((n,tm):xs)
>              | (Just tm') <- lookup n xs
>                  = if (ueq tm tm')  -- Take account of names! == no good.
>                       then checkAcc xs
>                       else ifail $ ICantUnify (Ind tm) (Ind tm')
>              | otherwise = checkAcc xs

>          loc x xs = loc' 0 x xs
>          loc' i x ((n,_):xs) | x == n = i
>                              | otherwise = loc' (i+1) x xs
>          loc' i x [] = -1

An equality test which takes account of names which should be equal.
TMP HACK! ;)

>          ueq :: TT Name -> TT Name -> Bool
>          ueq x y = case unifyenv emptyGam [] (Ind x) (Ind y) of
>                   Right _ -> True
>                   _ -> False

Grr!

> ueq :: Gamma Name -> TT Name -> TT Name -> Bool
> ueq gam x y = case unifyenv gam [] (Ind x) (Ind y) of
>                   Right _ -> True
>                   _ -> False


 substNames :: [(Name,TT Name)] -> TT Name -> TT Name
 substNames [] tm = tm
 substNames ((n,t):xs) tm = substNames xs (substName n t (Sc tm))

Look for a specific term (unifying with a subterm)
and replace it.

> unifySubstTerm :: Gamma Name -> TT Name -> TT Name ->
>                   Scope (TT Name) -> TT Name
> unifySubstTerm gam p tm (Sc x) = p' x where
>     p' x | ueq gam x p = tm
>     p' (App f' a) = (App (p' f') (p' a))
>     p' (Bind n b (Sc sc)) = (Bind n (fmap p' b) (Sc (p' sc)))
>      --   | n == p = (Bind n (fmap p' b) (Sc sc))
>      --   | otherwise
>     p' (Proj n i x) = Proj n i (p' x)
>     p' (Label t (Comp n cs)) = Label (p' t) (Comp n (map p' cs))
>     p' (Call (Comp n cs) t) = Call (Comp n (map p' cs)) (p' t)
>     p' (Return t) = Return (p' t)
>     p' (Stage (Quote t)) = Stage (Quote (p' t))
>     p' (Stage (Code t)) = Stage (Code (p' t))
>     p' (Stage (Eval t ty)) = Stage (Eval (p' t) (p' ty))
>     p' (Stage (Escape t ty)) = Stage (Escape (p' t) (p' ty))
>     p' x = x

