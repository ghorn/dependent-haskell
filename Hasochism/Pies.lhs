%if False

> {-# LANGUAGE GADTs, PolyKinds, KindSignatures, MultiParamTypeClasses,
>     DataKinds, FlexibleInstances, RankNTypes, FlexibleContexts,
>     TypeOperators, TypeFamilies, ScopedTypeVariables #-}

> module Pies where
>
> import NatVec
> import Control.Applicative
> import Data.Foldable
> import Data.Traversable

%endif

%format :**: = ":\!\!*\!*\!\!:"
%format :&&: = ":\!\!\&\!\&\!\!:"

 
%format natter = "\F{natter}"
%format natty = "\F{natty}"
%format vcopies = "\F{vcopies}"
%format vapp = "\F{vapp}"
%format pure = "\F{pure}"
%format traverse = "\F{traverse}"

%format fmap = "\F{fmap}"
%format fmapDefault = "\F{fmapDefault}"
%format foldMapDefault = "\F{foldMapDefault}"
%format foldMap = "\F{foldMap}"

We have already seen that singletons like |Natty| simulate a dependent
dynamic explicit quantifier, corresponding to the explicit $\Pi$-type
of type theory: Agda's $(x\!:\!S)\to T$. Implementations of type
theory, following Pollack's lead, often support a dependent dynamic
\emph{implicit} quantifier, the $\{x\!:\!S\}\to T$ of Agda, allowing
type constraints to induce the synthesis of useful information. The method
is Milner's---substitution arising from unification problems generated by
the typechecker---but the direction of inference runs from types to programs,
rather than the other way around.

The Haskell analogue of the implicit $\Pi$ is constructed with
singleton \emph{classes}. For example, the following |NATTY| type
class defines a single method |natty|, delivering the |Natty|
singleton corresponding to each promoted |Nat|. A |NATTY| number is
known at run time, despite not being given explicitly.

> class NATTY (n :: Nat) where
>   natty :: Natty n
> 
> instance NATTY Z where
>   natty = Zy
> 
> instance NATTY n => NATTY (S n) where
>   natty = Sy natty

For example, we may write a more implicit version of |vtake|:

%format vtrunc = "\F{vtrunc}"

> vtrunc :: NATTY m => Proxy n -> Vec (m :+ n) x -> Vec m x
> vtrunc = vtake natty

The return type determines the required length, so we can leave
the business of singleton construction to instance inference.

< > vtrunc Proxy (1 :> 2 :> 3 :> 4 :> V0) :: Vec (S (S Z)) Int
< 1 :> 2 :> V0

\subsection{Instances for Indexed Types}

It is convenient to omit singleton arguments when the machine can
figure them out, but we are entitled to ask whether the additional
cost of defining singleton classes as well as singleton types
worth the benefit. However, there is a situation where we have no
choice but to work implicitly: we cannot abstract an |instance|
over a singleton type, but we can constrain it. For example, the
|Applicative| instance for vectors requires a |NATTY| constraint.

> instance NATTY n => Applicative (Vec n) where
>   pure   = vcopies natty
>   (<*>)  = vapp

where |vcopies| needs to inspect a run time length to make the right number of
copies---we are obliged to define a helper function:

> vcopies :: forall n x. Natty n -> x -> Vec n x
> vcopies  Zy      x  =  V0
> vcopies  (Sy n)  x  =  x :> vcopies n x   

Meanwhile, |vapp| is pointwise application, requiring only static knowledge
of the length.

> vapp :: forall n s t. Vec n (s -> t) -> Vec n s -> Vec n t
> vapp  V0         V0         = V0
> vapp  (f :> fs)  (s :> ss)  = f s :> vapp fs ss

We note that simply defining |(<*>)| by pattern matching in place

< instance NATTY n => Applicative (Vec n) where -- |BAD|
<   pure   = vcopies natty
<   V0         <*> V0         = V0
<   (f :> fs)  <*> (s :> ss)  = f s :> (fs <*> ss)

yields an error in the step case, where |n ~ S m| but |NATTY m| cannot
be deduced. \emph{We} know that the |NATTY n| instance must be a
|NATTY (S m)| instance which can arise only via an instance
declaration which presupposes |NATTY m|. However, such an argument via
`inversion' does not explain how to construct the method dictionary
for |NATTY m| from that of |NATTY (S m)|. When we work with |Natty|
explicitly, the corresponding inversion is just what we get from
pattern matching. The irony here is that |(<*>)| does not need the
singleton at all!

Although we are obliged to define the helper functions, |vcopies| and
|vapp|, we could keep them local to their usage sites inside the
instance declaration.  We choose instead to expose them: it can be
convenient to call |vcopies| rather than |pure| when a |Natty n| value
is to hand but a |NATTY n| dictionary is not; |vapp| needs neither.

To finish the |Applicative| instance, we must ensure that |Vec n| is
a |Functor|. In fact, vectors are |Traversable|, hence also |Foldable|
|Functor|s in the default way, without need for a |NATTY|
constraint.
                             
> instance Traversable (Vec n) where
>   traverse f V0 = pure V0
>   traverse f (x :> xs) = (:>) <$> f x <*> traverse f xs
>
> instance Foldable (Vec n) where
>   foldMap = foldMapDefault
>
> instance Functor (Vec n) where
>   fmap = fmapDefault

\subsection{Matrices and a Monad}

It is quite handy that |Vec n| is both |Applicative| and |Traversable|.
If we define a |Matrix| as a vertical vector of horizontal vectors, thus
(arranging |Matrix|'s arguments conveniently for the tiling library later
in the paper),

%format unMat = "\F{unMat}"

> data Matrix :: * -> (Nat, Nat) -> * where
>   Mat :: {unMat :: Vec h (Vec w a)} -> Matrix a (Pair w h)

%if False

> instance Show x => Show (Matrix x (Pair w h)) where
>   show = show . (foldMap ((:[]) . foldMap (:[]))) . unMat

%endif

we get transposition cheaply, provided we know the width.

%format xpose = "\F{transpose}"
%format sequenceA = "\F{sequenceA}"

> xpose :: NATTY w => Matrix a (Pair w h) -> Matrix a (Pair h w)
> xpose = Mat . sequenceA . unMat

The width information really is used at run time, and is otherwise
unobtainable in the degenerate case when the height is |Z|: |xpose| must
know how many |V0|s to deliver.

%format join = "\F{join}"

Completists may also be interested to define the |Monad| instance
for vectors whose |join| is given by the diagonal of a matrix.
This fits the |Applicative| instance, whose |(<*>)| method more directly
captures the notion of `corresponding positions'.

%format vhead = "\F{vhead}"
%format vtail = "\F{vtail}"
%format diagonal = "\F{diag}"

> vtail :: Vec (S n) x -> Vec n x
> vtail (_ :> xs)  = xs
>
> diagonal :: Matrix x (Pair n n) -> Vec n x
> diagonal (Mat V0)                 = V0
> diagonal (Mat ((x :> _) :> xss))  = x :> diagonal (Mat (fmap vtail xss))
>
> instance NATTY n => Monad (Vec n) where
>   return = pure
>   xs >>= f = diagonal (Mat (fmap f xs))

Gibbons (in communication with McBride and Paterson) notes that the
|diagonal| construction for unsized lists does not yield a monad, because
the associativity law fails in the case of `ragged' lists of lists. By
using sized vectors, we square away the problem cases.


\subsection{Exchanging Explicit and Implicit}

Some interplay between the explicit and implicit $\Pi$-types is
inevitable.  Pollack wisely anticipated situations where argument
synthesis fails because the constraints are too difficult or too few,
and provides a way to override the default implicit behaviour
manually. In Agda, if $f : \{x\!:\!S\}\to T$, then one may write
$f\:\{s\}$ to give the argument.

The Hindley-Milner type system faces the same issue: even though
unification is more tractable, we still encounter terms like |const
True undefined :: Bool| where we do not know which type to give
|undefined|----parametric polymorphism ensures that we don't need to
know. As soon as we lose parametricity, e.g. in |show . read|, the
ambiguity of the underconstrained type is a problem and rightly yields
a type error. The `manual override' takes the form of a type annotation,
which may need to refer to type variables in scope.

As we have already seen, the |natty| method allows us to extract an
explicit singleton whenever we have implicit run time knowledge of a value.
Occasionally, however, we must work the other way around. Suppose we have
an explicit |Natty n| to hand, but would like to
use it in a context with an implicit |NATTY n| type class constraint.
We can cajole GHC into building us a |NATTY n| dictionary as follows:
 
> natter :: Natty n -> (NATTY n => t) -> t
> natter  Zy      t  =  t
> natter  (Sy n)  t  =  natter n t

This is an obfuscated identity function, but not in the way that it
looks.  The |t| being passed along recursively is successively but
silently precomposed with the dictionary transformer generated from
the |instance NATTY n => NATTY (S n)| declaration. Particularly
galling, however, is the fact that the dictionary thus constructed
contains just an exact replica of the |Natty n| value which |natter| has
traversed.

We have completed a matrix of dependent quantifiers, shown here for the
paradigmatic example of natural numbers,
\[
\begin{array}{||r||||c||c||}
\hline
     & \textbf{implicit} & \textbf{explicit} \\
\hline
\hline
\textbf{static} & |forall ((n :: Nat)).| & |forall ((n :: Nat)). Proxy n ->| \\
\hline
\textbf{dynamic} & |forall n. NATTY n =>| & |forall n. Natty n ->| \\
\hline
\end{array}
\]
involving the kind |Nat|, and two ways (neither of which is the type |Nat|) to
give its inhabitants run time representation, |NATTY| and |Natty|, which are
only clumsily interchangeable despite the former wrapping the latter. We could
(and in the Strathclyde Haskell Enhancement, did) provide a more pleasing
notation to make the dynamic quantifiers look like $\Pi$-types and their
explicit instantiators look like ordinary data, but the awkwardness is more
than skin deep.

%$%

