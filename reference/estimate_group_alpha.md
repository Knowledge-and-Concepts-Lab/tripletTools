# Jointly estimate a group-level choice-model shape and refine the group embedding

[`run_group_embedding_from_list`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/run_group_embedding_from_list.md)
always fits the group embedding under the crowd-kernel choice model
(\\\alpha = 1\\ on the Student-t continuum used throughout this
package's recovery/validation work: \\\alpha = 1\\ is exactly
crowd-kernel \\\mu = 1\\, \\\alpha \to \infty\\ is the exact Gaussian
limit). This function takes that fit as a starting point and alternates,
via coordinate ascent, between (1) re-estimating \\\alpha\\ by profiled
maximum likelihood with the embedding held fixed, and (2) refitting the
embedding under the current \\\alpha\\, warm-started from the previous
iteration – the group-level analogue of the per-participant joint
estimation done by `condor_joint_manifold_workflow.py`'s update step
([`vignette("condor_workflows_vignette")`](https://knowledge-and-concepts-lab.github.io/tripletTools/articles/condor_workflows_vignette.md),
Workflow 4), but simpler: there is only one \\\alpha\\ and one embedding
to estimate, so no cross-participant pooling or empirical-Bayes
shrinkage is needed.

## Usage

``` r
estimate_group_alpha(
  triplet_list,
  warm_start,
  max_epochs = 50000L,
  tolerance = 1e-04,
  tol_window = 10000L,
  seed = 222L,
  device = NULL,
  norm_penalty = 0,
  max_outer = 15L,
  tol_log_alpha = 0.05,
  alpha_grid = 10^seq(log10(2e-04), log10(2e+06), length.out = 140),
  verbose = TRUE
)
```

## Arguments

- triplet_list:

  A named list of data frames, one per participant, as returned by
  [`get.combined`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/get.combined.md)
  – the same object passed to
  [`run_group_embedding_from_list`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/run_group_embedding_from_list.md)
  to produce `warm_start`. Must contain genuine
  `sampleAlg == "validation"` trials (see Details).

- warm_start:

  Numeric matrix giving the starting embedding: one row per item (row
  names = item names) and `d` columns, typically the `embedding`
  returned by a prior call to
  [`run_group_embedding_from_list`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/run_group_embedding_from_list.md)
  on the same `triplet_list`. Required – this function refines an
  already-fit embedding rather than fitting one from scratch. `d` is
  taken from `ncol(warm_start)`.

- max_epochs, tolerance, tol_window, device, norm_penalty:

  Same meaning as the matching arguments of
  [`run_group_embedding_from_list`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/run_group_embedding_from_list.md),
  applied to every embedding-refit step.

- seed:

  Integer random seed, used for the train/test shuffling fallback (when
  `triplet_list` has no usable `sampleSet` split) and as the embedding
  fit's `random_state` at every outer iteration.

- max_outer:

  Maximum number of coordinate-ascent iterations. Default `15`.

- tol_log_alpha:

  Convergence threshold on the log scale: stop once the re-estimated
  \\\alpha\\ changes by less than this between iterations. Default
  `0.05`.

- alpha_grid:

  Candidate \\\alpha\\ values for the profiled maximum-likelihood step
  at each iteration.

- verbose:

  Logical; print one line of progress per outer iteration. Default
  `TRUE`.

## Value

A named list with five elements:

- `embedding`:

  Numeric matrix, the final refit embedding (item names as row names,
  `dim_0`/`dim_1`/... columns).

- `alpha`:

  Final estimated \\\alpha\\.

- `log_alpha`:

  `log(alpha)`.

- `ci`:

  95\\ \\\alpha\\ at the final iteration.

- `history`:

  Data frame with one row per outer iteration: `iter`, `alpha`, `ll_val`
  (validation log-likelihood at the re-estimated \\\alpha\\), `acc_val`
  (validation accuracy), `epoch` (embedding-refit stopping epoch), and
  `delta_log_alpha`.

## Details

\\\alpha\\ is re-estimated at each iteration using only
`sampleAlg == "validation"` trials – genuinely held out, never used to
fit the embedding at any iteration. This is deliberate: profiling
\\\alpha\\ on the same trials the embedding was just optimized against
would let the \\\alpha\\ estimate chase training noise the embedding has
already been shaped to fit, rather than measuring real choice-model
shape. `triplet_list` must therefore contain real validation trials (see
[`set_validation_behavior`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/set_validation_behavior.md)/[`assign_sample_sets`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/assign_sample_sets.md)
to designate some, or
[`find_frequent_triplets`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/find_frequent_triplets.md)/
[`assign_validation_from_frequency`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/assign_validation_from_frequency.md)
to retrofit a validation set onto legacy data that predates that
convention).

Iteration stops once the re-estimated \\\alpha\\ changes by less than
`tol_log_alpha` (on the log scale) from the previous iteration, or after
`max_outer` iterations, whichever comes first.

## What this does and does not estimate

Unlike the per-participant joint workflow, there is no population of
noisy per-person \\\alpha\\ estimates to shrink toward each other here –
a single \\\alpha\\ is estimated from the whole pooled dataset directly,
with no regularization pulling it back if it is poorly identified. Check
`ci` (the final iteration's 95\\ confidence interval) before trusting
the point estimate, especially on a small dataset or at large \\\alpha\\
(the Student-t kernel converges to Gaussian as \\\alpha\\ grows, so the
profile likelihood flattens and \\\alpha\\ becomes harder to pin down
precisely, even though validation accuracy itself is structurally
insensitive to \\\alpha\\ for this choice-model family and so cannot
reveal this on its own).

## Examples

``` r
if (FALSE) { # \dontrun{
grp <- run_group_embedding_from_list(icon_triplets, d = 3L)
joint <- estimate_group_alpha(icon_triplets, warm_start = grp$embedding)
joint$alpha
joint$history
} # }
```
