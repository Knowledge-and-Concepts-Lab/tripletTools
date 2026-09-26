# Align multiple embeddings into one shared reference frame

Iteratively Procrustes-aligns every embedding in `elist` onto a common
consensus configuration (Gower, 1975), rather than aligning pairs of
embeddings independently against each other. This is the natural
preprocessing step before averaging or otherwise directly comparing
coordinates across more than two embeddings, since plain pairwise
alignment (as used internally by
[`get.rep.dist`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/get.rep.dist.md))
only ever produces a shared frame for one pair at a time.

## Usage

``` r
generalized_procrustes(
  elist,
  scale = TRUE,
  reflect = TRUE,
  max_iter = 100,
  tol = 1e-06
)
```

## Arguments

- elist:

  List of embeddings. Each element should be a matrix or data frame of
  coordinates for the same items in the same order, with the same
  dimensionality across all embeddings.

- scale:

  Logical. Allow rescaling each embedding's overall size during
  alignment (in addition to rotation/reflection/translation)? Default
  `TRUE`, matching
  [`get.rep.dist`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/get.rep.dist.md)'s
  default Procrustes convention.

- reflect:

  Logical. Allow reflection during alignment? Default `TRUE` –
  embeddings fit independently (e.g. one per participant) can come out
  mirror-flipped with no meaningful interpretation attached to the
  reflection itself.

- max_iter:

  Integer. Maximum number of alignment iterations. Default 100.

- tol:

  Numeric. Convergence tolerance: iteration stops once the consensus
  configuration's root-mean-square change between iterations drops below
  this value. Default `1e-6`.

## Value

A list with elements:

- `aligned`:

  A list the same length and names as `elist`, each embedding
  rotated/reflected/scaled onto the shared consensus frame.

- `consensus`:

  The final consensus configuration (matrix, same dimensions as one
  embedding): the mean of `aligned`.

- `iterations`:

  Number of iterations actually run.

- `converged`:

  Logical: did the consensus change drop below `tol` before `max_iter`
  was reached?

## Details

Starting from an arbitrary initial reference (the first embedding in
`elist`), each embedding is Procrustes-aligned onto the current
consensus
([`procrustes`](https://vegandevs.github.io/vegan/reference/procrustes.html),
target-based, not `symmetric = TRUE` – there is always a well-defined
target here, the running consensus, unlike a pairwise comparison between
two embeddings with no natural reference), the consensus is recomputed
as the mean of the newly-aligned embeddings, and this repeats until the
consensus stops changing (or `max_iter` is reached). Unlike pairwise
alignment, every embedding ends up in one shared coordinate frame
simultaneously, so coordinates can be directly compared, combined, or
averaged across any subset of embeddings – exactly what
[`smooth_embedding_trajectory`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/smooth_embedding_trajectory.md)
needs before it can average coordinates across participants.

## References

Gower, J.C. (1975). Generalized Procrustes analysis. Psychometrika,
40(1), 33-51.

## Examples

``` r
if (FALSE) { # \dontrun{
gpa <- generalized_procrustes(icon_emb_ind)
gpa$consensus
gpa$converged
} # }
```
