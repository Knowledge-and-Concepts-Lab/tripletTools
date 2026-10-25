# Summarize a joint-manifold Condor workflow run

Reads the output directory of `condor_joint_manifold_workflow.py`
(package `inst/condor/`) and produces a self-contained Markdown report
covering the diagnostics this project has repeatedly needed by hand for
each new dataset run through that workflow: whether the per-participant
position *and* alpha estimates actually converged (estimated
independently of each other – geometry position and choice-model shape
are not tied to a single shared curve; see
`condor_joint_manifold_update.R`'s own documentation for why), and –
when the original triplet data is supplied – whether the kernel-smoothed
production estimate beats each participant's own individual embedding on
held-out validation trials, with the embedding-pooling and
alpha-shrinkage contributions to that advantage reported separately (not
just their combined effect, which conflates the two – see *Why the
decomposition, not just one comparison* below).

## Usage

``` r
summarize_joint_estimation(
  output_dir,
  triplet_data = NULL,
  run_loo_check = TRUE,
  fit_sample_alg = "random",
  val_trialtype = "validation",
  oscillation_window = 5,
  oscillation_threshold = 0.1,
  item_colors = NULL,
  n_geometry_panels = 6,
  output_md = NULL,
  verbose = TRUE
)
```

## Arguments

- output_dir:

  Path to a `condor_joint_manifold_workflow.py` output directory (must
  contain `run_manifest.txt`, `setup/worker_ids.txt`, and
  `setup/item_order.txt` – written by that workflow's resume-support
  code).

- triplet_data:

  `NULL` (default), or a combined triplet data frame in this package's
  standard format (`Center`/`Left`/
  `Right`/`Answer`/`sampleAlg`/`worker_id` columns – the same shape
  [`get.combined`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/get.combined.md)
  produces, or one element of `icon_triplets`/`color_triplets` row-bound
  together). When supplied, this is the *original* raw triplet data
  (including validation trials), not anything already inside
  `output_dir` – validation trials are deliberately never passed to the
  Condor workflow itself (see
  [`assign_sample_sets()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/assign_sample_sets.md)'s
  `"holdout"` mode), so there is no way to recover them from
  `output_dir` alone. If `NULL`, the held-out comparison and
  leave-one-out check are skipped and the report says so.

- run_loo_check:

  Logical. When `triplet_data` is supplied, also run
  [`loo_trajectory_accuracy`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/loo_trajectory_accuracy.md)
  (fully out-of-sample, no alpha component, not expensive – refits a
  simple kernel-smoothed trajectory once per participant using each
  participant's *original* embedding, not the full joint alternating
  procedure). Default `TRUE`.

- fit_sample_alg, val_trialtype:

  Which `sampleAlg`/trial type counts as fitting vs. held-out data,
  passed to the internal trial-list builder and to
  [`loo_trajectory_accuracy`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/loo_trajectory_accuracy.md)'s
  `trialtype`. Defaults `"random"` and `"validation"`, matching this
  project's standard convention.

- oscillation_window, oscillation_threshold:

  A participant is flagged as possibly not converged if their position's
  range (or, separately, their log-alpha's range – position and alpha
  are estimated independently now, so each gets its own convergence
  check) over the last `oscillation_window` outer iterations exceeds
  `oscillation_threshold` times the full sample's final-iteration range
  on that same scale. Defaults 5 and 0.1 – tuned against a real
  non-convergent position case (oscillation amplitude ~0.35 against a
  full range of ~1.4, comfortably above this threshold) and several
  genuinely converged boundary cases (recent-iteration range under
  0.01). Not a universal constant; adjust if a dataset's own position or
  alpha scale makes the default too strict or too lax.

- item_colors:

  Character vector, same length and order as `setup/item_order.txt`, or
  `NULL` (default): colors for the embedding-geometry grid. With no
  dataset-specific semantics available in general, the default colors
  items by their position in `item_order.txt` via
  [`rainbow`](https://rdrr.io/r/grDevices/palettes.html); pass a
  semantically meaningful vector (e.g. an
  [`hsv()`](https://rdrr.io/r/grDevices/hsv.html) scheme keyed to known
  item properties) for a more informative plot.

- n_geometry_panels:

  Integer, number of evenly-spaced query points across the recovered
  position range to show in the embedding-geometry grid. Default 6. Only
  plotted when `d` (read from `run_manifest.txt`) is 2 or 3; skipped
  (with a note in the report) otherwise.

- output_md:

  Path to write the Markdown report to. Default
  `file.path(output_dir, "summary.md")`. Figures are written as PNG
  files to a sibling `<name>_files/` directory and referenced with
  relative paths, so the report is self-contained if copied as a unit.

- verbose:

  Logical, print progress. Default `TRUE`.

## Value

Invisibly, a list with the parsed run (`run`), the convergence
diagnostics (`position_flags`, `alpha_flags`), and – when `triplet_data`
was supplied – the comparison table (`decomposition`) and the
leave-one-out result (`loo`, or `NULL` if `run_loo_check = FALSE`). Also
writes `output_md` and its figures as a side effect.

## Why the decomposition, not just one comparison

The production comparison (pooled estimate vs. each participant's own
embedding) differs from the baseline in two ways at once: a pooled vs.
individual embedding, *and* a shrinkage-regularized vs. fixed (alpha
= 1) choice-model noise parameter. A win on that comparison alone does
not say which component is responsible – alpha-shrinkage alone could
help even if the embedding geometry carries no real cross-participant
structure at all, simply by partially pooling a single scalar noise
parameter toward a population mean. This function reports all four
combinations (own/pooled embedding x alpha=1/shrunk) so that conclusion
doesn't have to be taken on faith; see the `triplet_choice_and_loss.Rmd`
analysis (outside this package, in the lab's own research documentation)
this was first worked out in for a worked example on real data, where
embedding-pooling alone (holding alpha fixed) already recovered most of
the combined effect – and where that same analysis went on to test
whether alpha's regularization needed to be tied to geometric position
at all (an earlier design this workflow used) and found no advantage to
doing so, which is why alpha is decoupled from position in the current
design.

There is a second, independent confound even within "embedding-pooling
alone": the kernel-smoothed pooled estimate differs from a participant's
own embedding both by averaging in other participants *and* by being
evaluated at that participant's own recovered *position* – itself a free
parameter fit to that participant's own training data. A plain,
position-independent grand mean (the same embedding for every
participant) isolates the first effect without the second. Comparing it
to the position-weighted pooled estimate answers whether a participant's
own position is doing anything beyond ordinary variance-reduction from
averaging – on one real dataset analyzed this way, the two were
statistically indistinguishable (no evidence of real position-dependent
structure, just noise reduction), while on another they were not (the
position-weighted estimate did reliably better, consistent with a real
individual-differences axis).
