# Test whether two groups' embeddings differ reliably

Fits a separate group embedding for each of two participant groups and
measures how well they Procrustes-align, then compares that alignment to
a null distribution built by repeatedly re-partitioning the pooled
participants at random (preserving the true groups' sizes) and measuring
the same alignment between the resulting pseudo-groups. If the true
groups align reliably *worse* than random partitions of the same sizes
do, that's evidence the groups differ in how they represent the items –
beyond what's expected from ordinary between-participant variability
alone.

## Usage

``` r
group_difference_test(
  triplet_list,
  group,
  d,
  n_permutations = 999L,
  seed = 1,
  max_epochs = 50000L,
  tolerance = 1e-04,
  tol_window = 10000L,
  device = NULL,
  geometry = c("euclidean", "sphere"),
  radius = 1,
  norm_penalty = 0,
  verbose = TRUE
)
```

## Arguments

- triplet_list:

  A named list of data frames, one per participant, as returned by
  [`get.combined`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/get.combined.md).
  Names identify participants (worker IDs).

- group:

  Group membership for each participant: either a named vector (names =
  worker IDs matching `triplet_list`) or a data frame with columns
  `worker_id` and `group`. Must cover exactly the same worker IDs as
  `triplet_list`, with exactly two distinct values.

- d:

  Embedding dimensionality, held fixed across every fit (the true split
  and every null permutation). Choose this beforehand – e.g. via
  [`estimate_dimensionality`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/estimate_dimensionality.md)
  on the pooled data – rather than re-selecting it per permutation,
  which would be prohibitively slow and would also entangle
  dimensionality selection with the group-difference test itself.

- n_permutations:

  Number of null (random-partition) replicates. Default `999L`. Each
  replicate needs 2 full embedding fits, so this function is
  compute-heavy – see *Details* for the Condor-based companion for
  larger-scale runs.

- seed:

  Integer random seed for reproducibility, both for the random
  participant partitions and (derived per fit) each embedding's own
  fitting seed. Default `1`.

- max_epochs, tolerance, tol_window, device, geometry, radius,
  norm_penalty:

  Forwarded to
  [`run_group_embedding_from_list`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/run_group_embedding_from_list.md)
  for every fit (the true split and every null permutation).

- verbose:

  Logical. If `TRUE` (default), print progress as each replicate is fit.

## Value

An object of class `"group_difference_test"`: a named list with
elements:

- `observed_correlation`:

  The Procrustes correlation between the two true groups' embeddings
  (via
  [`get.rep.dist`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/get.rep.dist.md)).

- `null_correlations`:

  Numeric vector of length `n_permutations`: the same correlation for
  each random same-sized partition of the pooled participants.

- `p_value`:

  One-sided permutation p-value,
  `(1 + sum(null_correlations <= observed_correlation)) / (1 + n_permutations)`
  – small when the true groups align reliably worse than random
  partitions do.

- `settings`:

  The arguments this call was made with, plus `group_levels` and
  `group_sizes`.

## Details

Null replicates are drawn at the *same sizes* as the true groups (not a
blanket 50/50 split), since embedding quality depends on how much data
went into it – comparing an unequal true split against evenly-sized
random halves would confound sample-size differences with genuine group
differences.

This function is meant for small-scale or exploratory use: every
replicate (the true split plus each of `n_permutations` null partitions)
requires two full embedding fits, run serially. For a large-scale run,
`inst/condor` ships a companion HTCondor workflow
(`condor_group_diff_workflow.py`) implementing the same procedure (same
size-matched null partitioning, same one-sided p-value), dispatched as
many independent per-replicate jobs rather than run serially in one R
session. The two are independent implementations of the same statistical
procedure, not guaranteed to reproduce identical numbers given "the
same" seed (participant partitioning uses R's vs. Python's own random
number generator) – only the same logic.

## Examples

``` r
if (FALSE) { # \dontrun{
# icon_triplets has 6 participants; split into two groups of 3
ids <- names(icon_triplets)
group <- setNames(rep(c("A", "B"), each = 3), ids)

result <- group_difference_test(
  icon_triplets, group, d = 3L,
  n_permutations = 99L, max_epochs = 5000L
)
result$observed_correlation
result$p_value
} # }
```
