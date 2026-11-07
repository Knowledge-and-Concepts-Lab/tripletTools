# Standard group-embedding workflow: dimensionality, final fit, choice-model refit

Chains together the three steps of this package's standard recipe for
producing a production group embedding:

1.  **Dimensionality.**
    [`estimate_dimensionality`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/estimate_dimensionality.md)
    searches over `dims` under the crowd-kernel choice model (\\\alpha =
    1\\), selecting `best_d` via its one-standard-error rule.

2.  **Final fit.**
    [`run_group_embedding_from_list`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/run_group_embedding_from_list.md)
    is called `n_restarts_final` times at `best_d`, each from an
    independent random initialization, keeping whichever restart
    achieves the lowest test loss. This is a dedicated refit, not a
    reuse of one of the embeddings fitted during step 1 – see the *Why a
    dedicated final fit* section below.

3.  **Choice-model refit.**
    [`estimate_group_alpha`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/estimate_group_alpha.md)
    takes the winning final fit as a warm start and coordinate-ascends
    between re-estimating the Student-t/crowd-kernel shape \\\alpha\\
    and refitting the embedding under it, using held-out
    `sampleAlg == "validation"` trials to profile \\\alpha\\.

## Usage

``` r
run_group_embedding_workflow(
  triplet_list,
  dims = 1:8,
  n_restarts_dim = 10L,
  n_restarts_final = 5L,
  internal_test_frac = 0.1,
  max_epochs = 50000L,
  tolerance = 1e-04,
  tol_window = 10000L,
  device = NULL,
  seed = 1L,
  geometry = c("euclidean", "sphere"),
  radius = 1,
  norm_penalty = 0,
  best_d_norm_penalty = NULL,
  refit_alpha = TRUE,
  max_outer = 15L,
  tol_log_alpha = 0.05,
  alpha_grid = 10^seq(log10(2e-04), log10(2e+06), length.out = 140),
  verbose = TRUE
)
```

## Arguments

- triplet_list:

  A named list of data frames, one per participant, as returned by
  [`get.combined`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/get.combined.md).
  Must contain a usable `sampleSet` column (see
  [`assign_sample_sets`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/assign_sample_sets.md))
  and, if `refit_alpha = TRUE`, genuine `sampleAlg == "validation"`
  trials (see
  [`estimate_group_alpha`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/estimate_group_alpha.md)).

- dims:

  Integer vector of dimensionalities to evaluate in step 1. Default
  `1:8`.

- n_restarts_dim:

  Random restarts per dimension in step 1, forwarded to
  [`estimate_dimensionality`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/estimate_dimensionality.md)'s
  `n_restarts`. Default `10L`.

- n_restarts_final:

  Independent random restarts for the dedicated final fit in step 2; the
  restart with the lowest test loss is kept. Default `5L`. Each restart
  uses seed `seed + (r - 1) * 1000`, the same restart-seed formula used
  throughout this package's Condor workflows.

- internal_test_frac, max_epochs, tolerance, tol_window, device,
  norm_penalty:

  Forwarded to
  [`estimate_dimensionality`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/estimate_dimensionality.md)
  (step 1) and
  [`run_group_embedding_from_list`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/run_group_embedding_from_list.md)
  (step 2); `max_epochs`, `tolerance`, `tol_window`, `device`, and
  `norm_penalty` are also forwarded to
  [`estimate_group_alpha`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/estimate_group_alpha.md)
  (step 3). `internal_test_frac` is only used by step 1 (see that
  function's own documentation).

- seed:

  Base integer seed. Step 1 receives it directly; step 2's restarts
  derive `seed + (r - 1) * 1000` from it; step 3 receives it directly as
  its own `seed`.

- geometry:

  Either `"euclidean"` (default) or `"sphere"`, forwarded to steps 1
  and 2.
  [`estimate_group_alpha`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/estimate_group_alpha.md)
  (step 3) does not currently support `geometry = "sphere"`; this
  function errors clearly if `geometry = "sphere"` and
  `refit_alpha = TRUE` rather than silently refitting a Euclidean
  embedding when a spherical one was requested. Set
  `refit_alpha = FALSE` to use spherical geometry for steps 1-2 alone.

- radius:

  Sphere radius when `geometry = "sphere"`. Default `1`.

- best_d_norm_penalty:

  Forwarded to
  [`estimate_dimensionality`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/estimate_dimensionality.md).
  Default `NULL` (equal to `norm_penalty`).

- refit_alpha:

  Logical; if `TRUE` (default), run step 3. Set to `FALSE` to stop after
  the final fit (step 2) – e.g. when `triplet_list` has no
  `sampleAlg == "validation"` trials yet.

- max_outer, tol_log_alpha, alpha_grid:

  Forwarded to
  [`estimate_group_alpha`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/estimate_group_alpha.md)
  (step 3); ignored if `refit_alpha = FALSE`.

- verbose:

  Logical; print a progress line at the start of each step and for each
  final-fit restart. Default `TRUE`. Forwarded to
  [`estimate_dimensionality`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/estimate_dimensionality.md)
  and
  [`estimate_group_alpha`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/estimate_group_alpha.md).

## Value

A named list with four elements:

- `dimensionality`:

  The full return value of
  [`estimate_dimensionality`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/estimate_dimensionality.md)
  (step 1): `results` and `summary`.

- `best_d`:

  The selected dimensionality (smallest `d` with
  `summary$best_d == TRUE`).

- `final_fit`:

  The winning restart's return value from
  [`run_group_embedding_from_list`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/run_group_embedding_from_list.md)
  (step 2): `embedding`, `loss`, `history` – the crowd-kernel (\\\alpha
  = 1\\) production embedding at `best_d`.

- `refit`:

  `NULL` if `refit_alpha = FALSE`; otherwise the return value of
  [`estimate_group_alpha`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/estimate_group_alpha.md)
  (step 3): `embedding` (the refit geometry), `alpha`, `log_alpha`,
  `ci`, `history`.

## Why a dedicated final fit

Steps 1 and 3 both already exist as standalone functions; what this
wrapper adds is the final-fit step in between, plus the glue to chain
all three. Reusing the single best-loss embedding that happened to come
out of step 1's (dimension, restart) grid would tie the production
embedding to whatever restart budget that grid spent per dimension –
necessarily small, since it is multiplied across every dimension in
`dims`. A dedicated final-fit step is a one-time cost (not multiplied by
a dimension grid), so it is the cheapest place in the whole workflow to
spend extra restart budget on the one embedding that is actually used
downstream. This mirrors `inst/condor/condor_workflow.py`'s existing
three-stage Condor architecture (dimensionality search, learning curve,
final embedding fit), which already treats the final fit as a separate
stage rather than a reuse of a dimensionality-search artifact; the
Condor workflow's own final stage (`condor_fit.R`, `stage == "final"`)
gained the same `n_restarts`-and-keep-lowest-loss logic for the same
reason.

Picking the lowest test loss among `n_restarts_final` restarts is a mild
"best of k" selection, so that restart's own test loss is a slightly
optimistic estimate of its true generalization loss – the same kind of
optimism inherent in selecting `best_d` itself. This is a standard,
usually small effect with `k` in the single digits, not something this
function tries to correct for.

## Dimension estimation and the test set

`estimate_dimensionality`'s internal `sampleSet == "test"` pool is never
touched during dimensionality search (see that function's own *Internal
test set and restart variability* section) – it is reserved for this
function's step 2, exactly as
[`run_group_embedding_from_list`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/run_group_embedding_from_list.md)
uses it. That means the same `sampleSet` train/test split, assigned once
upstream (e.g. via
[`assign_sample_sets`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/assign_sample_sets.md)),
is reused consistently across all three steps of this workflow – the
dimensionality search is not re-randomizing or resampling that top-level
split per restart; the resampling it does do (see
`estimate_dimensionality`'s `internal_test_frac`) happens entirely
within the `"train"` pool, matched across every dimension for a given
restart so dimension comparisons stay apples-to-apples.

## Examples

``` r
if (FALSE) { # \dontrun{
out <- run_group_embedding_workflow(
  triplet_list     = icon_triplets,
  dims             = 1:6,
  n_restarts_dim   = 5L,
  n_restarts_final = 5L
)
out$best_d
out$final_fit$embedding       # crowd-kernel (alpha = 1) production embedding
out$refit$embedding           # choice-model-refit embedding
out$refit$alpha               # estimated choice-model shape parameter

# Stop after the final fit (e.g. no validation trials available yet)
out2 <- run_group_embedding_workflow(icon_triplets, refit_alpha = FALSE)
out2$refit  # NULL
} # }
```
