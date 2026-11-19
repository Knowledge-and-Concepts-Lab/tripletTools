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
  alpha_test_frac = 0.5,
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
  to produce `warm_start`. Must contain a usable `sampleSet` column (see
  Details); no longer requires `sampleAlg == "validation"` trials (see
  the section above).

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
  `triplet_list` has no usable `sampleSet` split), for the
  `alpha_test_frac` split of the `test` pool (see above), and as the
  embedding fit's `random_state` at every outer iteration.

- alpha_test_frac:

  Proportion of the `sampleSet == "test"` pool set aside to profile
  \\\alpha\\, drawn once (not re-split per outer iteration) via
  [`sample_internal_test`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/sample_internal_test.md).
  The remaining `1 - alpha_test_frac` continues to do early stopping for
  the embedding refit. Must satisfy `0 < alpha_test_frac < 1`. Default
  `0.5`.

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

  Logical; print the alpha-test/checkpoint-selection split sizes once up
  front, then one line of progress per outer iteration. Default `TRUE`.

## Value

A named list with seven elements:

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

  Data frame with one row per outer iteration: `iter`, `alpha`,
  `ll_alpha_test` (log-likelihood on the alpha-test pool at the
  re-estimated \\\alpha\\), `acc_alpha_test` (accuracy on that same
  pool), `epoch` (embedding-refit stopping epoch), and
  `delta_log_alpha`.

- `n_test_fit`:

  Row count of the sub-pool used for the embedding refit's own early
  stopping.

- `n_alpha_test`:

  Row count of the sub-pool used to profile \\\alpha\\.

## Details

Iteration stops once the re-estimated \\\alpha\\ changes by less than
`tol_log_alpha` (on the log scale) from the previous iteration, or after
`max_outer` iterations, whichever comes first.

## Where alpha is profiled from, and why not sampleAlg == "validation"

\\\alpha\\ must be re-estimated at each iteration on trials that never
influenced the embedding – profiling it on the same trials the embedding
was just shaped to fit (directly, via the gradient step, or indirectly,
via early-stopping checkpoint selection) would let the \\\alpha\\
estimate chase sample-specific noise rather than measuring real
choice-model shape. An earlier version of this function used
`sampleAlg == "validation"` trials for this, since those are this
package's existing convention for a trial pool nothing else ever
touches. That has a real cost on datasets where validation trials are
the whole point of calling this function in the first place: it leaves
nothing genuinely untouched afterward to report the finished (embedding,
\\\alpha\\) pair's quality against, since the one trial pool designed
for that
([`get.hoacc`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/get.hoacc.md)'s
`trialtype = "validation"`) has itself just been used as a tuning input.

The actual requirement for a clean \\\alpha\\-profiling pool is
disjointness from whatever selected the embedding – it does not have to
be literally labeled `sampleAlg == "validation"`. This function instead
splits the `sampleSet == "test"` pool itself (via
[`sample_internal_test`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/sample_internal_test.md),
the same mechanism
[`estimate_dimensionality`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/estimate_dimensionality.md)
uses to carve `internal_test` out of `sampleSet == "train"`) into two
disjoint parts, fixed once for the whole coordinate-ascent run:
`alpha_test_frac` of it is set aside purely to profile \\\alpha\\ (step
1), and the rest continues to do early stopping/checkpoint selection for
the embedding refit (step 2), exactly the role the full `test` pool
would otherwise play. Neither sub-pool ever touches `train`. Any real
`sampleAlg == "validation"` trials in `triplet_list` are therefore left
completely untouched by this function – free to serve afterward as an
honest, never-used final-quality check on the finished model.

The cost is the mirror image of the problem this solves: splitting
`test` further means less data for checkpoint selection, which gets
somewhat noisier. On a dataset with abundant randomly-sampled trials
(the usual case for the legacy data this is meant to help with) that's a
far better place to absorb the cost than shrinking an already-scarce
validation pool.

## What this does and does not estimate

Unlike the per-participant joint workflow, there is no population of
noisy per-person \\\alpha\\ estimates to shrink toward each other here –
a single \\\alpha\\ is estimated from the whole pooled dataset directly,
with no regularization pulling it back if it is poorly identified. Check
`ci` (the final iteration's 95\\ confidence interval) before trusting
the point estimate, especially on a small dataset or at large \\\alpha\\
(the Student-t kernel converges to Gaussian as \\\alpha\\ grows, so the
profile likelihood flattens and \\\alpha\\ becomes harder to pin down
precisely, even though alpha-test accuracy itself is structurally
insensitive to \\\alpha\\ for this choice-model family and so cannot
reveal this on its own).

## Examples

``` r
if (FALSE) { # \dontrun{
grp <- run_group_embedding_from_list(icon_triplets, d = 3L)
joint <- estimate_group_alpha(icon_triplets, warm_start = grp$embedding)
joint$alpha
joint$history

# Any real sampleAlg == "validation" trials in icon_triplets are left
# untouched by the call above -- safe to use afterward for an honest
# final check, e.g.:
# get.hoacc(joint$embedding, icon_triplets[[1]], trialtype = "validation")
} # }
```
