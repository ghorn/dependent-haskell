%if False

> {-# LANGUAGE GADTs, PolyKinds, KindSignatures, MultiParamTypeClasses,
>     DataKinds, FlexibleInstances, RankNTypes, FlexibleContexts,
>     TypeOperators, TypeFamilies #-}

> module Editor where
>
> import Prelude hiding (mapM_)
>
> import Control.Applicative
> import Data.Traversable
> import Data.Foldable
>
> import Foreign
> import Foreign.C (CInt(..))
> import ANSIEscapes
> import System.IO
> import System.Environment
>
> import NatVec
> import BoxPleasure

> (/+/) :: Natty m -> Natty n -> Natty (m :+ n)
> Zy   /+/ n    = n
> Sy m /+/ n   = Sy (m /+/ n)

> class NATTY (n :: Nat) where
>   natty :: Natty n
> 
> instance NATTY Z where
>   natty = Zy
> 
> instance NATTY n => NATTY (S n) where
>   natty = Sy natty
> 
> natter :: Natty n -> (NATTY n => t) -> t
> natter Zy     t = t
> natter (Sy n) t = natter n t

> vlength :: Vec n x -> Natty n
> vlength V0        = Zy
> vlength (x :> xs) = Sy (vlength xs)

> vcopies :: forall n x.Natty n -> x -> Vec n x
> vcopies Zy x = V0
> vcopies (Sy n) x = x :> vcopies n x   
> 
> vapp :: forall n s t.Vec n (s -> t) -> Vec n s -> Vec n t
> vapp V0 V0 = V0
> vapp (f :> fs) (s :> ss) = f s :> vapp fs ss
 
> instance NATTY n => Applicative (Vec n) where
>   pure = vcopies natty where
>   (<*>) = vapp where
> 
> instance Traversable (Vec n) where
>   traverse f V0 = pure V0
>   traverse f (x :> xs) = (:>) <$> f x <*> traverse f xs

%$

> instance Functor (Vec n) where
>   fmap = fmapDefault
> 
> instance Foldable (Vec n) where
>   foldMap = foldMapDefault


> data Matrix :: * -> (Nat, Nat) -> * where
>   Mat :: Vec h (Vec w a) -> Matrix a (Pair w h)
>
> unMat :: Matrix a (Pair w h) -> Vec h (Vec w a)
> unMat (Mat vs) = vs

%endif

\subsection{Character matrix boxes}

We implement a text editor using a character matrix box to represent
the text buffer.

> type CharMatrix = Matrix Char
> type CharBox wh = Box CharMatrix wh

We can fill an entire matrix with the same character.
 
> matrixChar :: Char -> (Natty w, Natty h) -> CharMatrix (Pair w h)
> matrixChar c (w, h) = Mat (vcopies h (vcopies w c))

We can render a character matrix box as a character matrix.

> renderCharBox ::
>   Size w h -> CharBox (Pair w h) -> CharMatrix (Pair w h)
> renderCharBox _       (Stuff css)        = css
> renderCharBox (w, h)  Clear              =
>   matrixChar ' ' (w, h)
> renderCharBox (w, _)  (Ver h1 b1 h2 b2)  =
>   Mat (unMat (renderCharBox (w, h1) b1)
>     `vappend` unMat (renderCharBox (w, h2) b2))
> renderCharBox (_, h) (Hor w1 b1 w2 b2)   =
>   Mat (  vcopies h vappend `vapp`
>          unMat (  renderCharBox (w1, h) b1) `vapp`
>                   unMat (renderCharBox (w2, h) b2))

We can display a character matrix as a list of strings.

> stringsOfCharMatrix :: CharMatrix wh -> [String]
> stringsOfCharMatrix (Mat vs) =
>   foldMap ((:[]) . foldMap (:[])) vs

In order to be able to cut (and hence crop) matrix boxes we
instantiate the |Cut| type class for matrices.

> instance Cut (Matrix e) where
>   horCut m _ (Mat ess) =
>     (Mat (fst <$> ps), Mat (snd <$> ps)) where
>       ps = vchop m <$> ess
>   verCut m _ (Mat ess) = (Mat tess, Mat bess) where
>     (tess, bess) = vchop m ess 

%$

\subsection{Existentials}

%format wrapNat = "\F{wrapNat}"
%format wrapPair = "\F{wrapPair}"
%format wrapInt = "\F{wrapInt}"
%format wrapSize = "\F{wrapSize}"
%format wrapPoint = "\F{wrapPoint}"
%format wrapRegion = "\F{wrapRegion}"
%format wrapVec = "\F{wrapVec}"
%format wrapLenVec = "\F{wrapLenVec}"
%format wrapString = "\F{wrapString}"
%format wrapStrings = "\F{wrapStrings}"

%format intToNat = "\F{intToNat}"
%format unFlip = "\F{unFlip}"
%format unLenVec = "\F{unLenVec}"
%format unSizeCharBox = "\F{unSizeCharBox}"

%format :**: = ":\!\!*\!*\!\!:"
%format :&&: = ":\!\!\&\!\&\!\!:"

%if False

> data Ex (p :: k -> *) where
>   Ex :: p i -> Ex p

> type WNat = Ex Natty

> wrapNat :: Nat -> WNat
> wrapNat  Z      =  Ex Zy
> wrapNat  (S m)  =  case wrapNat m of
>                    Ex n -> Ex (Sy n)

%endif

In Section~\ref{sec:merge-sort} we introduced existentially quantified
singletons as a means for taking dynamic values and converting them
into equivalent singletons.

We now present combinators for more interesting existentials. For the
editor we will need to generate a region, that is, a pair of pairs of
singleton naturals from a pair of pairs of natural numbers.

> data (p :: j -> *) :**: (q :: k -> *) :: (j, k) -> * where
>   (:&&:) :: p j -> q k -> (p :**: q) (Pair j k)
>
> wrapPair :: (a -> Ex p) ->
>             (b -> Ex q) ->
>               (a, b) -> Ex (p :**: q)
> wrapPair w1 w2 (x1, x2) =
>   case (w1 x1, w2 x2) of
>     (Ex v1, Ex v2) -> Ex (v1 :&&: v2)

The type |p :**: q| allows us to construct the type of pairs of |p|
and |q| singletons. The |wrapPair| function wraps a pair of dynamic
objects in a suitable existential package.

> type WPoint = Ex (Natty :**: Natty)
> type WSize = Ex (Natty :**: Natty)
> type WRegion = Ex ((Natty :**: Natty) :**: (Natty :**: Natty))

> intToNat :: Int -> Nat
> intToNat 0 = Z
> intToNat n = S (intToNat (n-1))

> wrapInt = wrapNat . intToNat
> wrapPoint  = wrapPair wrapInt wrapInt
> wrapSize   = wrapPair wrapInt wrapInt
> wrapRegion = wrapPair wrapPoint wrapSize

We might wish to wrap vectors, but the |Vec| type takes the length
index first, so we cannot us it as is with |Ex|. Thus we can define
and use a |Flip| combinator, which reverses the arguments of a two
argument type-operator.

> newtype Flip f a b = Flip {unFlip :: f b a}

> type WVec a = Ex (Flip Vec a)

> wrapVec :: [a] -> WVec a
> wrapVec []      = Ex (Flip V0)
> wrapVec (x:xs)  = case wrapVec xs of
>   Ex (Flip v) -> Ex (Flip (x :> v))

In fact, we will need to wrap a vector up along with its length, so
instead of using |Flip| we define an auxiliary |newtype| as follows:

> newtype LenVec a n = LenVec {unLenVec :: (Natty n, Vec n a)}

> type WLenVec a = Ex (LenVec a)

> wrapLenVec :: [a] -> WLenVec a
> wrapLenVec []      = Ex (LenVec (Zy, V0))
> wrapLenVec (x:xs)  = case wrapLenVec xs of
>   Ex (LenVec (n, v)) -> Ex (LenVec (Sy n, x :> v))

< newtype SizeCharBox w h =
<   SizeCharBox {unSizeCharBox :: (Size w h, CharBox (Pair w h))}

Oops... this isn't going to work with |Ex| because |SizeCharBox| takes two arguments.

> data SillySize (wh :: (Nat, Nat)) where
>   SillySize :: Natty w -> Natty h -> SillySize (Pair w h)

> newtype SizeCharBox wh =
>   SizeCharBox {unSizeCharBox :: (SillySize wh, CharBox wh)}

> type WCB = Ex SizeCharBox

> wrapString' :: String -> WCB
> wrapString' s = case wrapLenVec s of
>   Ex (LenVec (n, v)) ->
>     Ex (SizeCharBox (SillySize n (Sy Zy), Stuff (Mat (pure v))))

> wrapStrings' :: [String] -> WCB
> wrapStrings' []      = Ex (SizeCharBox (SillySize Zy Zy, Clear))
> wrapStrings' (s:ss)  =
>   case (wrapString' s, wrapStrings' ss) of
>     (  Ex (SizeCharBox (SillySize w1 h1, b1)),
>        Ex (SizeCharBox (SillySize w2 h2, b2))) ->
>          Ex (SizeCharBox (  SillySize (w1 `maxn` w2) (h1 /+/ h2),
>                             joinV (w1, h1) (w2, h2) b1 b2))



[old text]


%% > data WrappedVec a :: * where
%% >   WVec :: Vec n a -> WrappedVec a
%% >
%% > wrapList :: [a] -> WrappedVec a
%% > wrapList []      = WVec V0
%% > wrapList (x:xs)  = case wrapList xs of
%% >   WVec v -> WVec (x :> v)

Given a string of length |w|, we can wrap it as a character box of
size |(w, 1)|.

> data WCharBox :: * where
>   WCharBox :: Size w h -> CharBox (Pair w h) -> WCharBox
>
> wrapString :: String -> WCharBox
> wrapString s = case wrapLenVec s of
>   Ex (LenVec (n, v)) ->
>     WCharBox (n, Sy Zy) (Stuff (Mat (pure v)))

Given a list of |h| strings of maximum length |w|, we can wrap it as a
character box of size |(w, h)|.

> wrapStrings :: [String] -> WCharBox
> wrapStrings []      = WCharBox (Zy, Zy) Clear
> wrapStrings (s:ss)  =
>   case (wrapString s, wrapStrings ss) of
>     (WCharBox (w1, h1) b1, WCharBox (w2, h2) b2) ->
>       WCharBox
>         (w1 `maxn` w2, h1 /+/ h2)
>         (joinV (w1, h1) (w2, h2) b1 b2)


\subsection{Cursors}

Zippers~\cite{Huet97}.

> type Cursor a m = ([a], m, [a])
> type StringCursor = Cursor Char ()
> 
> type TextCursor = Cursor String StringCursor
> 
> deactivate :: Cursor a () -> (Int, [a])
> deactivate c = outward 0 c where
>   outward i ([], (), xs)     = (i, xs)
>   outward i (x : xz, (), xs) = outward (i + 1) (xz, (), x : xs)
> 
> activate :: (Int, [a]) -> Cursor a ()
> activate (i, xs) = inward i ([], (), xs) where
>   inward _ c@(_, (), [])     = c
>   inward 0 c                 = c
>   inward i (xz, (), x : xs)  = inward (i - 1) (x : xz, (), xs)
> 
> whatAndWhere :: TextCursor -> (WCharBox, (Int, Int))
> whatAndWhere (czz, cur, css) = (wrapStrings strs, (x, y))
>   where
>     (x, cs) = deactivate cur
>     (y, strs) = deactivate (czz, (), cs : css)

%if False

> data ArrowDir = UpArrow | DownArrow | LeftArrow | RightArrow
> data Modifier = Normal | Shift | Control
> 
> data Key
>   = CharKey Char                -- an ordinary printable character
>   | ArrowKey Modifier ArrowDir  -- an arrow key
>   | Return
>   | Backspace
>   | Delete
>   | Quit
> 
> directions :: [(Char, ArrowDir)]
> directions = [('A', UpArrow), ('B', DownArrow),
>               ('C', RightArrow), ('D', LeftArrow)]
> 
> escapeKeys :: [(String, Key)]
> escapeKeys =
>   [([c], ArrowKey Normal d) | (c, d) <- directions] ++
>   [("1;2" ++ [c], ArrowKey Shift d) | (c, d) <- directions] ++
>   [("1;5" ++ [c], ArrowKey Control d) | (c, d) <- directions] ++
>   [("3~", Delete)]
> 
> data Damage
>   = NoChange       -- nothing at all happened
>   | PointChanged   -- we moved the cursor but kept the text
>   | LineChanged    -- we changed text only on the current line
>   | LotsChanged    -- we changed text off the current line
>   deriving (Show, Eq, Ord)
 
%% > {--------------------------------------------------------------------------}
%% > {- Given a Key and an initial TextCursor, either reject the keystroke or  -}
%% > {- return a modified cursor, with an overestimate of the damage we've     -}
%% > {- done.                                                                  -}
%% > {--------------------------------------------------------------------------}
%% > 

> handleKey :: Key -> TextCursor -> Maybe (Damage, TextCursor)
> handleKey (CharKey c) (sz, (cz, (), cs), ss) =
>   Just (LineChanged, (sz, (c : cz, (), cs), ss))
> handleKey (ArrowKey Normal LeftArrow) (sz, (c : cz, (), cs), ss) =
>   Just (PointChanged, (sz, (cz, (), c : cs), ss))
> handleKey (ArrowKey Normal RightArrow) (sz, (cz, (), c : cs), ss) =
>   Just (PointChanged, (sz, (c : cz, (), cs), ss))
> handleKey (ArrowKey Normal UpArrow) (sUp : sz, pos, ss) =
>   Just (PointChanged, (sz, activate (i, sUp), s : ss))
>     where
>       (i, s) = deactivate pos
> handleKey (ArrowKey Normal DownArrow) (sz, pos, sDown : ss) =
>   Just (PointChanged, (s : sz, activate (i, sDown), ss))
>     where
>       (i, s) = deactivate pos
> handleKey Return (sz, (cz, (), cs), ss) =
>   Just (LotsChanged, (prefix : sz, ([], (), cs), ss))
>   where
>     (_, prefix) = deactivate (cz, (), [])
> handleKey Delete (sz, (cz, (), c : cs), ss) =
>   Just (LineChanged, (sz, (cz, (), cs), ss))
> handleKey Backspace (sz, (c : cz, (), cs), ss) =
>   Just (LineChanged, (sz, (cz, (), cs), ss))
> handleKey Delete (sz, (cz, (), []), s : ss) =
>   Just (LotsChanged, (sz, (cz, (), s), ss))
> handleKey Backspace (s : sz, ([], (), cs), ss) =
>   Just (LotsChanged, (sz, (cz, (), cs), ss))
>            where
>              (cz, _, _) = activate (length s, s)
> handleKey _ _ = Nothing

%endif

\subsection{The inner loop}

We give a brief overview of the editor's inner loop. The full code is
available at:

  \url{https://github.com/slindley/dependent-haskell/tree/master/Box}

The current position in the text buffer is represented using a zipper
structure over an undindexed list of strings. The current position and
size of the screen is represented as two pairs of integers. On a
change to the buffer, the inner loop proceeds as follows.
\begin{itemize}
\item Wrap the current screen position and size as a singleton region
  using |wrapRegion|.
\item Unravel the zipper structure to reveal the underlying structure
  of the buffer as a list of strings.
\item Use |wrapStrings| to wrap the list of strings as a suitably
  indexed |CharBox|.
\item Crop the |CharBox| according to the wrapped singleton region.
  size.
\item Render the result as a list of strings using
  |stringsOfCharMatrix . renderCharBox|.
\end{itemize}

We take advantage of dependent types to ensure that cropping yields
boxes of the correct size. The rest of the editor does not use
dependent types. The wrapping functions convert non-dependent data
into equivalent dependent data. Rendering does the opposite.

%if False

> foreign import ccall
>   initscr :: IO () 
> 
> foreign import ccall "endwin"
>   endwin :: IO CInt
> 
> foreign import ccall "refresh"
>   refresh :: IO CInt
> 
> foreign import ccall "&LINES"
>   linesPtr :: Ptr CInt
> 
> foreign import ccall "&COLS"
>   colsPtr :: Ptr CInt
 
> scrSize :: IO (Int, Int)
> scrSize = do
>     lnes <- peek linesPtr
>     cols <- peek colsPtr
>     return (fromIntegral cols, fromIntegral lnes)
> 
> copies :: Int -> a -> [a]
> copies n a = take n (repeat a)
> 
> crlf :: IO ()
> crlf = putStr "\r\n"
> 
> putLn :: String -> IO ()
> putLn x = putStr x >> crlf
 
%% > -- onScreen c r
%% > --   c is where the cursor currently is
%% > --   r is where the viewport currently is
%% > --   the return value is an updated viewport
%% > --   containing c

> type UPoint = (Int, Int)
> type USize = (Int, Int)
> type URegion = (UPoint, USize)
>
> onScreen :: UPoint -> URegion -> URegion
> onScreen (cx, cy) ((px, py), s@(sw, sh))
>   = (( intoRange px cx sw, intoRange py cy sh), s)
>   where
>     intoRange i j x
>       | i <= j && j <= i + x = i   -- in range, no change
>       | otherwise = max 0 (j - div x 2)
 
> getEscapeKey :: [(String, Key)] -> IO (Maybe Key)
> getEscapeKey [] = return Nothing
> getEscapeKey sks = case lookup "" sks of
>   Just k -> return (Just k)
>   _ -> do
>     c <- getChar
>     getEscapeKey [(cs, k) | (d : cs, k) <- sks, d == c]
> 
> keyReady :: IO (Maybe Key)
> keyReady = do
>   b <- hReady stdin
>   if not b then return Nothing else do
>     c <- getChar
>     case c of
>       '\n' -> return $ Just Return
>       '\r' -> return $ Just Return
>       '\b' -> return $ Just Backspace
>       '\DEL' -> return $ Just Backspace
>       _ | c >= ' ' -> return $ Just (CharKey c)
>       '\ESC' -> do
>         b <- hReady stdin
>         if not b then return $ Just Quit else do
>           c <- getChar
>           case c of
>             '[' -> getEscapeKey escapeKeys
>             _ -> return $ Just Quit
>       _ -> return $ Nothing
 
> layout :: Size w h -> CharBox (Pair w h) -> [String]
> layout s l = stringsOfCharMatrix (renderCharBox s l)
> 
> outer :: URegion -> TextCursor -> IO ()
> outer ps tc = inner ps tc (whatAndWhere tc) LotsChanged
>   where
>   inner ps@(p, _) tc lc@(WCharBox (lw, lh) l, c@(cx, cy)) d = do
>     refresh
>     s' <- scrSize
>     let ps'@((px, py), (sw, sh)) = onScreen c (p, s')
>     let d' = if ps /= ps' then LotsChanged else d
>     case d' of
>       LotsChanged -> do
>         clearScreen
>         resetCursor
>         case wrapRegion ps' of
>           Ex ((x :&&: y) :&&: (w :&&: h)) -> do
>             let cropped = crop ((x, y), (w, h)) (lw, lh) l
>             mapM_ putStr (layout (w, h) cropped)
>       LineChanged -> do
>         resetCursor
>         down (cy - py)
>         case wrapRegion ((px, cy), (sw, 1)) of
>           Ex ((x :&&: y) :&&: (w :&&: h)) -> do
>             let cropped = crop ((x, y), (w, h)) (lw, lh) l
>             mapM_ putStr (layout (w, h) cropped)
>       _ -> return ()
>     if d' > NoChange then do
>       resetCursor
>       forward (cx - px)
>       down (cy - py)
>      else return ()
>     mc <- keyReady
>     case mc of
>       Nothing   -> inner ps' tc lc NoChange
>       Just Quit -> return ()
>       Just k    -> case handleKey k tc of
>         Nothing       -> inner ps' tc lc NoChange
>         Just (d, tc') -> inner ps' tc' (whatAndWhere tc') d
 
> main = do 
>   hSetBuffering stdout NoBuffering
>   hSetBuffering stdin NoBuffering
>   xs <- getArgs
>   s <- case xs of
>     [] -> return ""
>     (x : _) -> readFile x
>   let (l, ls) = case lines s of
>         [] -> ("", [])
>         (l : ls) -> (l, ls)
>   initscr
>   outer ((0, 0), (-1, -1)) ([], ([], (), l), ls)
>   endwin

%endif
