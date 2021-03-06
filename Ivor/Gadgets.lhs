> {-# OPTIONS_GHC -fglasgow-exts #-}

> module Ivor.Gadgets where

> class Forget a b | a->b where
>     forget :: a -> b

> traceIndex :: [a] -> Int -> String -> a
> traceIndex xs i str | length xs <= i = error $ " !! index too large: " ++ str
>                     | otherwise = xs!!i

> safeIndex :: [a] -> Int -> a -> a
> safeIndex xs i def | length xs <= i = def
>                    | otherwise = xs!!i

=================== Result Monad ========================

> data Result r 
>     = Success r
>     | Failure String
>  deriving (Show, Eq)

> instance Monad Result where
>     (Success r)   >>= k = k r
>     (Failure err) >>= k = Failure err
>     return              = Success
>     fail s              = Failure s

> instance Functor Result where
>     fmap f (Failure str) = Failure str
>     fmap f (Success s) = Success (f s)

====================== Snoc Lists ===========================

> data Spine x = Empty | Snoc (Spine x) x

> infix 5 ??
> (??) :: Spine x -> Int -> x
> (Snoc _ x) ?? 0 = x
> (Snoc xs _) ?? n | n>0 = xs ?? (n-1)
> (Snoc _ _) ?? _ = error "?? - negative index"

> end (Snoc sp x) = x
> start (Snoc sp x) = sp

> size :: Spine x -> Int
> size Empty = 0
> size (Snoc xs x) = 1+(size xs)

> lose :: Int -> Spine x -> Spine x
> lose 0 (Snoc xs x) = xs
> lose n (Snoc xs x) = (Snoc (lose (n-1) xs) x)

> listify :: Spine x -> [x]
> listify xs = list' [] xs
>   where list' acc Empty = acc
>         list' acc (Snoc xs x) = list' (x:acc) xs

> revlistify :: Spine x -> [x]
> revlistify Empty = []
> revlistify (Snoc xs x) = x:(revlistify xs)

> instance Functor Spine where
>     fmap f Empty = Empty
>     fmap f (Snoc sp x) = Snoc (fmap f sp) (f x)

========= Functions I want in the standard library... =========

> lookupM :: (Monad m, Eq a) => a -> [(a,b)] -> m b
> lookupM y [] = fail "Not found"
> lookupM y ((x,v):xs) | x == y = return v
>                      | otherwise = lookupM y xs

Look for a file in the current directory, then each directory listed
in turn. If present, return the contents, otherwise fail

> findFile :: [FilePath] -> FilePath -> IO String
> findFile fp fn = ff' (".":fp) fn
>   where ff' [] fn = fail "File not found in search path"
>         ff' (d:ds) fn = do
>                         catch (do content <- readFile $ d ++ "/" ++ fn
>                                   return content)
>                               (\e -> ff' ds fn)

> unJust :: Maybe a -> a
> unJust (Just a) = a