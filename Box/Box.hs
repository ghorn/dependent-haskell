{-# LANGUAGE DataKinds, KindSignatures, GADTs, TypeFamilies, TypeOperators,
    RankNTypes, PolyKinds, ScopedTypeVariables #-}

module Box where
 
import Data.Monoid
import Control.Applicative
import Data.Foldable
import Data.Traversable

data Nat = Z | S Nat

data Natty :: Nat -> * where
  Zy :: Natty Z
  Sy :: Natty n -> Natty (S n)

class NATTY (n :: Nat) where
  natty :: Natty n

instance NATTY Z where
  natty = Zy

instance NATTY n => NATTY (S n) where
  natty = Sy natty

-- natter effectively converts an explicit Natty to an implicit NATTY
natter :: Natty x -> (NATTY x => t) -> t
natter Zy     t = t
natter (Sy x) t = natter x t

type family (m :: Nat) :+ (n :: Nat) :: Nat
type instance Z :+ n = n
type instance S m :+ n = S (m :+ n)

(/+/) :: Natty m -> Natty n -> Natty (m :+ n)
Zy /+/ n = n
Sy m /+/ n = Sy (m /+/ n)

data Cmp :: Nat -> Nat -> * where
  LTNat :: ((Max x (x :+ S y) ~ (x :+ S y))) => Natty y -> Cmp x (x :+ S y)
  EQNat :: (Max x x ~ x) => Cmp x x
  GTNat :: ((Max (y :+ S x) y ~ (y :+ S x))) => Natty x -> Cmp (y :+ S x) y

cmp :: Natty x -> Natty y -> Cmp x y
cmp Zy Zy = EQNat
cmp Zy (Sy y) = LTNat y
cmp (Sy x) Zy = GTNat x
cmp (Sy x) (Sy y) = case cmp x y of
  LTNat z -> LTNat z
  EQNat -> EQNat
  GTNat z -> GTNat z

data CmpCuts :: Nat -> Nat -> Nat -> Nat -> * where
  LTCuts :: Natty b -> CmpCuts a (S b :+ c) (a :+ S b) c
  EQCuts :: CmpCuts a b a b
  GTCuts :: Natty b -> CmpCuts (a :+ S b) c a (S b :+ c)

cmpCuts :: ((a :+ b) ~ (c :+ d)) => Natty a -> Natty b -> Natty c -> Natty d -> CmpCuts a b c d
cmpCuts Zy b Zy     d  = EQCuts
cmpCuts Zy b (Sy c) d  = LTCuts c
cmpCuts (Sy a) b Zy d  = GTCuts a
cmpCuts (Sy a) b (Sy c) d = case cmpCuts a b c d of
  LTCuts z -> LTCuts z
  EQCuts -> EQCuts
  GTCuts z -> GTCuts z

{-
leftCan :: forall a b c t. ((a :+ b) ~ (a :+ c)) => Natty a -> Natty b -> Natty c -> ((b ~ c) => t) -> t
leftCan Zy b c t = t
leftCan (Sy a) b c t = leftCan a b c t

assocLR :: forall l a b c t. (l ~ ((a :+ b) :+ c)) => Natty a -> Natty b -> Natty c -> ((l ~ (a :+ (b :+ c))) => t) -> t
assocLR Zy b c t = t
assocLR (Sy a) b c t = assocLR a b c t
-}

data Box :: ((Nat, Nat) -> *) -> (Nat, Nat) -> * where
  Stuff :: p xy -> Box p xy
  Clear :: Box p xy
  Hor :: Natty x1 -> Box p '(x1, y) -> Natty x2 -> Box p '(x2, y) -> Box p '(x1 :+ x2, y)
  Ver :: Natty y1 -> Box p '(x, y1) -> Natty y2 -> Box p '(x, y2) -> Box p '(x, y1 :+ y2)

type s :-> t = forall i. s i -> t i

ebox :: (p :-> Box q) -> Box p :-> Box q
ebox f (Stuff b) = f b
ebox f Clear = Clear
ebox f (Hor x1 l x2 r) = Hor x1 (ebox f l) x2 (ebox f r)
ebox f (Ver y1 t y2 b) = Ver y1 (ebox f t) y2 (ebox f b)

class Cut (p :: (Nat, Nat) -> *) where
  horCut :: Natty xl -> Natty xr -> p '(xl :+ xr, y) -> (p '(xl, y), p '(xr, y))
  verCut :: Natty yt -> Natty yb -> p '(x, yt :+ yb) -> (p '(x, yt), p '(x, yb))

instance Cut p => Cut (Box p) where
  horCut xl xr (Stuff p) = (Stuff pl, Stuff pr) where (pl, pr) = horCut xl xr p
  horCut xl xr Clear = (Clear, Clear)
  horCut xl xr (Hor x1 b1 x2 b2) = case cmpCuts xl xr x1 x2 of
    LTCuts z -> let (ll, lr) = horCut xl (Sy z) b1 in (ll, Hor (Sy z) lr x2 b2)
    EQCuts -> (b1, b2)
    GTCuts z -> let (rl, rr) = horCut (Sy z) xr b2 in (Hor x1 b1 (Sy z) rl, rr)
  horCut xl xr (Ver y1 tb y2 bb) = (Ver y1 tl y2 bl, Ver y1 tr y2 br)
    where (tl, tr) = horCut xl xr tb ; (bl, br) = horCut xl xr bb

  verCut yl yr (Stuff p) = (Stuff pl, Stuff pr) where (pl, pr) = verCut yl yr p
  verCut yl yr Clear = (Clear, Clear)
  verCut yl yr (Ver y1 b1 y2 b2) = case cmpCuts yl yr y1 y2 of
    LTCuts z -> let (tt, tb) = verCut yl (Sy z) b1 in (tt, Ver (Sy z) tb y2 b2)
    EQCuts -> (b1, b2)
    GTCuts z -> let (bt, bb) = verCut (Sy z) yr b2 in (Ver y1 b1 (Sy z) bt, bb)
  verCut yl yr (Hor x1 tb x2 bb) = (Hor x1 tl x2 bl, Hor x1 tr x2 br)
    where (tl, tr) = verCut yl yr tb ; (bl, br) = verCut yl yr bb

instance Cut p => Monoid (Box p xy) where
  mempty = Clear
  mappend b Clear = b
  mappend Clear b' = b'
  mappend b@(Stuff _) _ = b
  mappend (Hor x1 b1 x2 b2) b' = Hor x1 (mappend b1 b1') x2 (mappend b2 b2')
    where (b1', b2') = horCut x1 x2 b'
  mappend (Ver y1 b1 y2 b2) b' = Ver y1 (mappend b1 b1') y2 (mappend b2 b2')
    where (b1', b2') = verCut y1 y2 b'

data Vec :: Nat -> * -> * where
  V0 :: Vec Z x
  (:>) :: x -> Vec n x -> Vec (S n) x

vlength :: Vec n x -> Natty n
vlength V0        = Zy
vlength (x :> xs) = Sy (vlength xs)

instance Show x => Show (Vec n x) where
  show = show . foldMap (:[])

vcopies :: forall n x.Natty n -> x -> Vec n x
vcopies Zy x = V0
vcopies (Sy n) x = x :> vcopies n x   

vapp :: forall n s t.Vec n (s -> t) -> Vec n s -> Vec n t
vapp V0 V0 = V0
vapp (f :> fs) (s :> ss) = f s :> vapp fs ss

instance NATTY n => Applicative (Vec n) where
  pure = vcopies natty where
  (<*>) = vapp where

instance Traversable (Vec n) where
  traverse f V0 = pure V0
  traverse f (x :> xs) = (:>) <$> f x <*> traverse f xs

instance Functor (Vec n) where
  fmap = fmapDefault

instance Foldable (Vec n) where
  foldMap = foldMapDefault

vappend :: Vec m x -> Vec n x -> Vec (m :+ n) x
vappend V0 ys = ys
vappend (x :> xs) ys = x :> vappend xs ys

vchop :: Natty m -> Natty n -> Vec (m :+ n) x -> (Vec m x, Vec n x)
vchop Zy n xs = (V0, xs)
vchop (Sy m) n (x :> xs) = (x :> ys, zs) where (ys, zs) = vchop m n xs

data Matrix :: * -> (Nat, Nat) -> * where
  Mat :: Vec y (Vec x a) -> Matrix a '(x, y)

unMat :: Matrix a '(x,y) -> Vec y (Vec x a)
unMat (Mat m) = m

instance Cut (Matrix e) where
  horCut xl xr (Mat ess) = (Mat (fst <$> lrs), Mat (snd <$> lrs)) where
    lrs = vchop xl xr <$> ess
  verCut yt yb (Mat ess) = (Mat tess, Mat bess) where
    (tess, bess) = vchop yt yb ess

{- smart constructors for clear boxes -}
clear :: (Natty x, Natty y) -> Box p '(x, y)
clear (x, y) = Clear

emptyBox :: Box p '(Z, Z)
emptyBox = Clear

hGap :: Natty x -> Box p '(x, Z)
hGap x = Clear

vGap :: Natty y -> Box p '(Z, y)
vGap y = Clear

{- placing boxes -}
type family Max (m :: Nat) (n :: Nat) :: Nat
type instance Max Z     n     = n
type instance Max (S m) Z     = S m
type instance Max (S m) (S n) = S (Max m n)

maxn :: Natty m -> Natty n -> Natty (Max m n)
maxn Zy     n      = n
maxn (Sy m) Zy     = Sy m
maxn (Sy m) (Sy n) = Sy (maxn m n)

{-
--- lemmas about max ---

-- we wire this knowledge into the Cmp datatype

maxAddR :: forall x y z t.Natty x -> Natty y -> ((Max x (x :+ S y) ~ (x :+ S y)) => t) -> t
maxAddR Zy     y t = t
maxAddR (Sy x) y t = maxAddR x y t

maxAddL :: forall x y z t.Natty x -> Natty y -> ((Max (x :+ S y) x ~ (x :+ S y)) => t) -> t
maxAddL x y t = maxAddR x y (maxSym x (x /+/ Sy y) t)

maxRefl :: forall x y t.Natty x -> ((Max x x ~ x) => t) -> t
maxRefl Zy     t = t
maxRefl (Sy x) t = maxRefl x t

maxSym :: forall x y t.Natty x -> Natty y -> ((Max x y ~ Max y x) => t) -> t
maxSym Zy Zy         t = t
maxSym Zy (Sy y)     t = t
maxSym (Sy x) Zy     t = t
maxSym (Sy x) (Sy y) t = maxSym x y t
------------------------
-}

-- place boxes horizontally
joinH' :: (Natty x1, Natty y1) -> (Natty x2, Natty y2) ->
            Box p '(x1, y1) -> Box p '(x2, y2) -> Box p '(x1 :+ x2, Max y1 y2)
joinH' (x1, y1) (x2, y2) b1 b2 =
  case cmp y1 y2 of
    EQNat ->
       (Hor x1 b1 x2 b2)
    LTNat n' ->
      (Hor x1 (Ver y1 b1 (Sy n') (clear (x1, Sy n'))) x2 b2)
    GTNat n' ->
       (Hor x1 b1 x2 (Ver y2 b2 (Sy n') (clear (x2, Sy n'))))
joinH :: (NATTY x1, NATTY y1, NATTY x2, NATTY y2) =>
           Box p '(x1, y1) -> Box p '(x2, y2) -> Box p '(x1 :+ x2, Max y1 y2)
joinH = joinH' (natty, natty) (natty, natty)

-- place boxes vertically
joinV' :: (Natty x1, Natty y1) -> (Natty x2, Natty y2) ->
            Box p '(x1, y1) -> Box p '(x2, y2) -> Box p '(Max x1 x2, y1 :+ y2)
joinV' (x1, y1) (x2, y2) b1 b2 =
  case cmp x1 x2 of
    EQNat    ->
       (Ver y1 b1 y2 b2)
    LTNat n' ->
      (Ver y1 (Hor x1 b1 (Sy n') (clear (Sy n', y1))) y2 b2)
    GTNat n' ->
       (Ver y1 b1 y2 (Hor x2 b2 (Sy n') (clear (Sy n', y2))))
joinV :: (NATTY x1, NATTY y1, NATTY x2, NATTY y2) =>
           Box p '(x1, y1) -> Box p '(x2, y2) -> Box p '(Max x1 x2, y1 :+ y2)
joinV = joinV' (natty, natty) (natty, natty)

{- cropping -}
type Size w h = (Natty w, Natty h)
type Point x y = (Natty x, Natty y)

type Region x y w h = (Point x y, Size w h)

cropBox :: Cut p => (Point x y, Size w h) -> Size r s -> Box p '(x :+ (w :+ r), y :+ (h :+ s)) -> Box p '(w, h)
cropBox ((x, y), (w, h)) (r, s) b =
  let (_, bxwr)   = horCut x (w /+/ r) b in
  let (bxw, _)    = horCut w r bxwr in
  let (_, bxwyhs) = verCut y (h /+/ s) bxw in
  let (bxwyh, _)  = verCut h s bxwyhs in
    bxwyh
    
cropBox' :: forall x y w h r s p.(NATTY r, NATTY s, Cut p) =>
              (Point x y, Size w h) -> Box p '(x :+ (w :+ r), y :+ (h :+ s)) -> Box p '(w, h)
cropBox' region box = cropBox region ((natty, natty) :: Size r s) box


