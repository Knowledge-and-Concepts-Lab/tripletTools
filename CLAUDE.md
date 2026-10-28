# tripletTools — Claude Code project context

## What this package is

An R package for loading, processing, and analysing data from triadic
comparison (triplet) studies. Participants judge which of two items is
more similar to a reference item. The package handles the full pipeline:
data loading → embedding → analysis → visualisation.

Current version: **0.2.0**. Package URL:
<https://knowledge-and-concepts-lab.github.io/tripletTools/>

------------------------------------------------------------------------

## Repository layout

    R/                        # All exported R functions
    inst/python/              # Bundled Python embedding backend
      compute_embeddings.py   # Entry point: train_embedding_model(), process_all_workers()
      salmon/                 # PyTorch triplet embedding library (vendored)
        triplets/
          offline.py          # OfflineEmbedding class
          samplers/adaptive/
            _embed.py         # Embedding, OGD, GD, Damper classes
            _noise_models.py  # CKL, TSTE, STE, GNMDS, SOE, Logistic noise models
            search/           # Information-gain query selection
    inst/requirements.txt     # conda packages for the Python env
    inst/condor/              # HTCondor workflows: pure-Python orchestrators (submit node,
                               #   no R needed there) dispatching per-job R scripts that run
                               #   inside the tripletTools container (built by
                               #   .github/workflows/docker-publish.yml). Four independent
                               #   workflows, each with its own orchestrator/per-job-script/
                               #   config-template/unittest set:
                               #   condor_workflow.py           - dimensionality search -> learning
                               #                                   curve -> final embedding fit
                               #                                   (condor_fit.R, params_template.yml)
                               #   condor_group_diff_workflow.py - group-difference permutation test,
                               #                                   Condor companion to the local R
                               #                                   function group_difference_test()
                               #                                   (condor_group_fit.R,
                               #                                   condor_group_compare.R,
                               #                                   group_diff_params_template.yml,
                               #                                   README_group_diff.md - CHTC deploy steps)
                               #   condor_individual_embeddings_workflow.py - one embedding per
                               #                                   worker_id, concatenated into a
                               #                                   single CSV; Condor companion to
                               #                                   run_embeddings_from_list()'s
                               #                                   per-individual output
                               #                                   (condor_individual_fit.R,
                               #                                   individual_embeddings_params_template.yml,
                               #                                   README_individual_embeddings.md)
                               #   condor_recovery_sweep_workflow.py - choice-model recovery sweep:
                               #                                   simulates n_replicates independent
                               #                                   synthetic ground-truth embeddings +
                               #                                   triplets under each of N "generating"
                               #                                   alphas (Student-t continuum; alpha=1 is
                               #                                   exactly Crowd Kernel mu=1, alpha=Inf is
                               #                                   the exact Gaussian/gamma=0.5 limit),
                               #                                   fits a recovery embedding under every
                               #                                   (replicate, generating, fitting) alpha
                               #                                   combination (one Condor job each -- e.g.
                               #                                   20 replicates x 8x8 alphas = 1280 jobs),
                               #                                   and scores Procrustes recovery error,
                               #                                   aggregated into a long-format CSV plus a
                               #                                   gen x fit mean/SD matrix. Replication is
                               #                                   what makes claims about specific
                               #                                   off-diagonal cells trustworthy rather
                               #                                   than single-draw noise. Takes no input
                               #                                   data file -- ground truth/triplet
                               #                                   simulation is done locally (stdlib
                               #                                   Python, no numpy) by the orchestrator
                               #                                   itself before any Condor job is queued.
                               #                                   One of two workflows here that bypass
                               #                                   train_embedding()'s CKL-only R wrapper,
                               #                                   calling compute_embeddings.py's
                               #                                   _fit_offline() directly via reticulate
                               #                                   to select any noise model/alpha (the other
                               #                                   is condor_joint_manifold_workflow.py, below)
                               #                                   (condor_recovery_fit.R,
                               #                                   recovery_sweep_params_template.yml,
                               #                                   README_recovery_sweep.md).
                               #                                   Companion tools, same directory:
                               #                                   condor_recovery_sweep_aggregate_only.py
                               #                                   (rerun just the final local aggregation
                               #                                   step against an already-populated
                               #                                   stage1_fit/), analyze_recovery_history.py
                               #                                   (offline replay of the early-stopping rule
                               #                                   against saved *_history.csv traces under
                               #                                   different candidate tolerance/tol_window
                               #                                   settings), condor_recovery_sweep_refit_capped.py
                               #                                   (re-fit only the cells that hit the original
                               #                                   run's epoch ceiling without genuinely
                               #                                   converging, at a higher max_epochs, reusing
                               #                                   the original stage0_simulate/ data and each
                               #                                   cell's exact original fit_seed, then merge
                               #                                   just those rows into results_long_refit.csv)
                               #   condor_joint_manifold_workflow.py - Condor-scale version of the fully-rigorous
                               #                                   joint geometry+choice-model manifold estimation
                               #                                   validated locally in condor_workflows_vignette.Rmd:
                               #                                   jointly estimates, per participant, a 1-D
                               #                                   manifold position determining BOTH a real
                               #                                   re-fit embedding (not just a kernel-weighted
                               #                                   average of others' existing fits) AND a choice-
                               #                                   model shape alpha(t) = exp(beta0+beta1*t), via
                               #                                   alternating coordinate ascent. The expensive step
                               #                                   (one real embedding refit per participant per
                               #                                   outer iteration) is embarrassingly parallel
                               #                                   within an iteration and runs on Condor
                               #                                   (condor_joint_manifold_fit.R, the other workflow
                               #                                   that bypasses the CKL-only R wrapper, same
                               #                                   _fit_offline()-via-reticulate pattern as the
                               #                                   recovery sweep above); the cheap per-iteration
                               #                                   update (GPA realignment, per-person position
                               #                                   search, population-curve refit) ALSO runs as its
                               #                                   own single Condor job in the same container
                               #                                   (condor_joint_manifold_update.R) -- not a local
                               #                                   Rscript call, after an initial version that ran
                               #                                   it locally turned out to need R on the submit
                               #                                   node, which a real submit node didn't have and
                               #                                   couldn't necessarily install (no special
                               #                                   permissions needed on the submit node at all, by
                               #                                   design, same as the other three workflows here).
                               #                                   Submits ONE Condor batch per outer iteration
                               #                                   covering every participant's refit at once (not
                               #                                   one batch per iteration-times-fold), to minimize
                               #                                   how many
                               #                                   rounds pay Condor's submission/queueing latency.
                               #                                   Only mode: fit (one joint estimate, no held-out
                               #                                   evaluation) is implemented; mode: loo (the full
                               #                                   leave-one-out validation used for the decisive
                               #                                   local test) is a planned follow-up
                               #                                   (joint_manifold_params_template.yml,
                               #                                   README_joint_manifold.md).
    vignettes/
      tripletTools.Rmd                  # "Get started" guide (name matches pkgname -- pkgdown auto-promotes it
                                         #   to a top-level navbar link instead of the Articles dropdown). Only
                                         #   vignette that isn't eval=FALSE throughout: Python-free chunks
                                         #   (bundled data, plot_pics(), get.hoacc()) are eval=TRUE and actually
                                         #   execute during the pkgdown build; Python-dependent chunks
                                         #   (setup_python_env(), embedding fitting) stay eval=FALSE since the
                                         #   pkgdown CI workflow has no conda/Python step.
      overview_vignette.Rmd
      read_data_vignette.Rmd            # Reading raw jsPsych exports and legacy CSVs into the package's
                                         #   standard triplet/embedding format (read_raw_data(), read_legacy(),
                                         #   get.combined()) -- not yet cross-referenced in this file's own
                                         #   "Recently added" history, found missing 2026-09-23 during a doc audit.
      embedding_vignette.Rmd            # Documents the full embedding pipeline (local: serial + future/plan
                                         #   multicore). HTCondor deployment itself now lives in
                                         #   condor_workflows_vignette.Rmd -- this vignette just points to it.
      comparing_embeddings_vignette.Rmd # Procrustes ceilings, classifier evaluation, successor representations
      condor_workflows_vignette.Rmd     # Deploying all three inst/condor/ workflows on HTCondor: submit-node
                                         #   setup (per-analysis sparse git clone), general deploy procedure,
                                         #   the shared container image, troubleshooting a stalled job, and one
                                         #   section per workflow. Supersedes the condor content that used to
                                         #   live at the end of embedding_vignette.Rmd.
      trajectory_vignette.Rmd           # generalized_procrustes()/smooth_embedding_trajectory()/
                                         #   plot_2d_trajectory()/plot_3d_trajectory() as an alternative to
                                         #   discrete clustering for individual differences, using the real,
                                         #   bundled color-triplets dataset (color_triplets/color_emb_ind/
                                         #   color_emb_group/color_lab). Not yet published outside a CogSci
                                         #   poster -- see the `color_triplets` roxygen @source.
    man/                      # Auto-generated by devtools::document() — do not edit
    docs/                     # pkgdown site — rebuild with pkgdown::build_site()

------------------------------------------------------------------------

## Python environment

- Conda environment name: `"triplet-embeddings"`
- Created once by
  [`setup_python_env()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/setup_python_env.md);
  activated automatically by `.onLoad`
- Packages: numpy\<2, pandas, torch, scikit-learn, scipy, skorch,
  setuptools\<71
- No pip installs — all conda (ensures DLL compatibility on Windows)
- `reticulate` is in **Suggests**, not Imports. All R code guards with
  [`requireNamespace("reticulate", quietly = TRUE)`](https://rdrr.io/r/base/ns-load.html)
  and uses `reticulate::` prefix

------------------------------------------------------------------------

## R function inventory

| Function | File | Purpose |
|----|----|----|
| [`setup_python_env()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/setup_python_env.md) | R/setup_python_env.R | One-time conda env creation |
| [`train_embedding()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/train_embedding.md) | R/train_embedding.R | Low-level: fit one embedding from matrices |
| [`run_group_embedding_from_list()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/run_group_embedding_from_list.md) | R/run_embeddings.R | Group embedding from triplet list |
| [`run_embeddings_from_list()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/run_embeddings_from_list.md) | R/run_embeddings.R | Per-participant (+ optional group, via `compute_group`) embeddings |
| [`run_embeddings()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/run_embeddings.md) | R/run_embeddings.R | Lower-level CSV-based pipeline; [`run_embeddings_from_list()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/run_embeddings_from_list.md) calls this internally (writes a temp pre-indexed CSV, then calls it) – [`run_group_embedding_from_list()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/run_group_embedding_from_list.md) does *not*, it calls [`train_embedding()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/train_embedding.md) directly instead |
| [`estimate_dimensionality()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/estimate_dimensionality.md) | R/estimate_dimensionality.R | Grid search over d with random restarts |
| [`matrix_rank()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/matrix_rank.md) | R/matrix_rank.R | Numerical rank of a (centered) matrix via SVD |
| [`procrustes_rank_ceiling()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/procrustes_rank_ceiling.md) | R/procrustes_rank_ceiling.R | Variance fraction captured by top-k dims of a target matrix |
| [`procrustes_spectral_ceiling()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/procrustes_spectral_ceiling.md) | R/procrustes_spectral_ceiling.R | Cosine similarity between two matrices’ singular-value spectra |
| [`hellinger_dist()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/hellinger_dist.md) | R/hellinger_dist.R | Pairwise Hellinger distances between rows of a profile matrix |
| [`successor_matrix()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/successor_matrix.md) | R/successor_matrix.R | Successor Representation from a weighted adjacency matrix |
| [`repeated_stratified_logistic_cv()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/repeated_stratified_logistic_cv.md) | R/repeated_stratified_logistic_cv.R | Repeated stratified CV logistic regression predicting a binary label from embedding coordinates |
| [`repeated_stratified_multinomial_cv()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/repeated_stratified_multinomial_cv.md) | R/repeated_stratified_multinomial_cv.R | Sibling of the above for \>2-class labels; [`nnet::multinom()`](https://rdrr.io/pkg/nnet/man/multinom.html)-backed, macro-averaged metrics + per-class breakdown |
| [`find_discriminating_triplets()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/find_discriminating_triplets.md) | R/find_discriminating_triplets.R | Finds triplets where two embeddings of the same items make discrepant CKL predictions, for designing a follow-up human study |
| [`group_difference_test()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/group_difference_test.md) | R/group_difference_test.R | Permutation test for whether two participant groups’ embeddings differ reliably; local (small-scale) companion to `inst/condor/condor_group_diff_workflow.py` |
| [`find_discrepant_items()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/find_discrepant_items.md) | R/find_discrepant_items.R | Ranks items by how much their distance-to-others profile differs between two embeddings; alignment-free alternative to per-item Procrustes residuals |
| [`find_frequent_triplets()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/find_frequent_triplets.md) | R/find_frequent_triplets.R | Ranks triplets by how many distinct participants judged them (left/right-independent, via [`make.tripnames()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/make.tripnames.md)), for retrofitting a post-hoc validation set onto legacy random-triplet data that predates the `sampleAlg == "validation"` convention |
| [`assign_validation_from_frequency()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/assign_validation_from_frequency.md) | R/assign_validation_from_frequency.R | Companion to [`find_frequent_triplets()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/find_frequent_triplets.md): sets `sampleAlg <- "validation"` on every matching trial for a given (already-thresholded) candidate set, with a per-participant cap on how many distinct triplets get promoted |
| [`reduce_embedding_dimension()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/reduce_embedding_dimension.md) | R/reduce_embedding_dimension.R | Reduces an embedding fit at a generously high `d` to the lowest dimension (via PCA) that preserves most of its variance, and reports triplet-prediction accuracy before/after |
| [`estimate_intrinsic_dimension()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/estimate_intrinsic_dimension.md) | R/estimate_intrinsic_dimension.R | Horn’s parallel analysis on the cMDS decomposition of a distance matrix (e.g. from [`get.rep.dist()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/get.rep.dist.md)) — estimates how many dimensions carry real, permutation-irreducible structure vs. noise. Used by [`test_for_clusters()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/test_for_clusters.md)’s `k_use` when not supplied directly. Also runs [`test_dominant_dimension()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/test_dominant_dimension.md) on the leading dimension by default (`test_dominance = TRUE`) |
| [`test_dominant_dimension()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/test_dominant_dimension.md) | R/test_dominant_dimension.R | Simulation-based (not permutation-based) significance test for whether one cMDS dimension’s share of variance exceeds a no-true-structure null — specifically targets the single-dominant-axis case [`estimate_intrinsic_dimension()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/estimate_intrinsic_dimension.md)’s own permutation test is conservative for |
| [`make.vmat()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/make.vmat.md) | R/make_vmat.R | Builds a subject-by-trial matrix and per-triplet majority vote from validation trials; also reports `n`/`nmaj`/`p`/`sig` – a one-sided binomial test of each triplet’s agreement level against chance (50/50) guessing |
| [`test_for_clusters()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/test_for_clusters.md) | R/test_for_clusters.R | Hopkins statistic (is there cluster structure at all?) + `mclust` BIC comparison (how many clusters?) on a participant distance matrix; also returns `model_name`/`classification` — the winning BIC model’s covariance-structure type and its own MAP hard assignment, for comparing against a separate hierarchical-clustering-based partition |
| [`test_cluster_stability()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/test_cluster_stability.md) | R/test_cluster_stability.R | Resampling (subsample-without-replacement) stability check for a chosen `hclust`+`cutree(k)` partition: refits on random participant subsets and compares each back to the full-data partition via Adjusted Rand Index, plus a per-participant co-clustering stability score |
| [`generalized_procrustes()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/generalized_procrustes.md) | R/generalized_procrustes.R | Iterative GPA (Gower, 1975): aligns *every* embedding in a list into one shared consensus frame simultaneously, unlike [`get.rep.dist()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/get.rep.dist.md)’s pairwise-only alignment. Prerequisite for [`smooth_embedding_trajectory()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/smooth_embedding_trajectory.md) |
| [`smooth_embedding_trajectory()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/smooth_embedding_trajectory.md) | R/smooth_embedding_trajectory.R | Kernel-weighted (Gaussian/Epanechnikov) average embedding at a grid of query points along a 1-D latent participant axis (e.g. `cmdscale(get.rep.dist(elist), k=1)`) — a continuous alternative to binning participants and averaging each bin separately. Returns Kish’s effective sample size per query point to flag boundary regions where the average is driven by only one or two participants. **Not safe for per-participant held-out prediction without [`loo_trajectory_accuracy()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/loo_trajectory_accuracy.md)** — see that function |
| [`loo_trajectory_accuracy()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/loo_trajectory_accuracy.md) | R/loo_trajectory_accuracy.R | Leave-one-out-corrected version of the “does the trajectory predict held-out judgments” workflow — fully excludes each participant (including from the 1-D axis itself) before computing the trajectory evaluated against them, fixing a real, confirmed data-leakage pitfall in the naive version of this analysis |
| [`plot_3d_trajectory()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/plot_3d_trajectory.md) | R/plot_3d_trajectory.R | 3-D scatterplot of one query point of a [`smooth_embedding_trajectory()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/smooth_embedding_trajectory.md) result (`scatterplot3d`, Suggests-only), with an `effective_n` strip along the bottom, a red marker at the query point shown, and (optional) small black dots marking real participants’ own positions along the same strip |
| [`plot_2d_trajectory()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/plot_2d_trajectory.md) | R/plot_3d_trajectory.R | Same as [`plot_3d_trajectory()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/plot_3d_trajectory.md) (same argument conventions, same bottom strip/marker/dots) but for 2-D embeddings, built on base [`graphics::plot()`](https://rdrr.io/r/graphics/plot.default.html) instead of `scatterplot3d` – no extra dependency |
| [`summarize_joint_estimation()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/summarize_joint_estimation.md) | R/summarize_joint_estimation.R | Reads a `condor_joint_manifold_workflow.py` output directory (`inst/condor/`) and writes a self-contained Markdown diagnostic report: independent per-participant position- and alpha-convergence flagging (geometry and alpha are decoupled, not a shared curve, so each gets its own spaghetti plot + oscillation detection), population-level alpha diagnostics (mean alpha / tau2 trajectory), an embedding-geometry grid (2-D/3-D), a descriptive final-alpha-vs-position scatter, and – when the original combined triplet data is supplied (never recoverable from `output_dir` alone, since validation trials are deliberately held out of the Condor workflow itself) – a 7-row own/pooled/grand-mean-embedding x alpha=1/shrunk-alpha decomposition (the grand-mean rows isolate whether a participant’s own recovered *position* adds anything beyond plain averaging across everyone) and a [`loo_trajectory_accuracy()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/loo_trajectory_accuracy.md) fully-out-of-sample confirmation |

Internal helpers in `R/zzz.R`: `.pkg_env`, `.onLoad`,
`.get_compute_py()`. Internal helpers in
`R/repeated_stratified_logistic_cv.R` (not exported): `make_binary()`,
`make_stratified_folds()`, `roc_auc()`, `classification_metrics()`.
Internal helpers in `R/find_discriminating_triplets.R` (not exported):
`ckl_prob()` (same formula/`mu` as the vendored Python CKL noise model),
`symmetric_kl_bernoulli()`. Internal helpers in
`R/repeated_stratified_multinomial_cv.R` (not exported):
`multinom_probs_matrix()` (normalizes
[`nnet::multinom`](https://rdrr.io/pkg/nnet/man/multinom.html)’s predict
output — returns a bare vector instead of a matrix for exactly 2
classes), `multiclass_metrics()`. Internal helpers in
`R/summarize_joint_estimation.R` (not exported):
`read_joint_manifold_run()`, `flag_unstable_joint_positions()`,
`flag_unstable_joint_alpha()` (same convergence check, applied to each
participant’s own alpha trajectory in log-alpha space – a separate check
from position’s now that the two are estimated independently),
`estimate_shrunk_alpha()` (per-person bounded-grid profiled MLE +
DerSimonian-Laird empirical-Bayes shrinkage, the fallback when a run
predates `final_alpha.csv`), `ckl_validation_eval()` (profiled
Student-t/crowd-kernel logLik+accuracy, a proper shared helper rather
than yet another duplicate of the formula repeated across the Condor R
scripts, since this one lives inside the package itself),
`build_jm_trial_lists()`, `compare_jm_conditions()`, `md_table()`.

------------------------------------------------------------------------

## Key architecture decisions

**Embedding pipeline flow (R → Python):**
[`train_embedding()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/train_embedding.md)
→ `compute_embeddings.py::train_embedding_model()` → `OfflineEmbedding`
→ `OGD` → `NeuralNet` (skorch) → PyTorch CKL noise model

**GPU/device support:** All functions accept `device = NULL`
(auto-selects CUDA → MPS → CPU) or an explicit PyTorch device string.
The `_auto_device()` helper in `_embed.py` handles auto-selection.
Tensors are moved to device in `_get_dists()`; results are moved back to
CPU before returning to R.

**Parallelism in
[`estimate_dimensionality()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/estimate_dimensionality.md):**
Uses
[`future.apply::future_lapply`](https://future.apply.futureverse.org/reference/future_lapply.html)
when `future.apply` is installed; falls back to `lapply`. The user sets
a [`future::plan()`](https://future.futureverse.org/reference/plan.html)
before calling — no changes needed to the call itself. `future.apply` is
in Suggests. Randomness is controlled by explicit `random_state`
integers derived from `seed`, so `future.seed = NULL` is correct.

**Random state:** `train_embedding_model()` accepts `random_state`; when
set it calls `np.random.seed()` and `torch.manual_seed()` before
constructing the model. Each (d, restart) pair in
[`estimate_dimensionality()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/estimate_dimensionality.md)
gets `seed + (restart-1)*1000 + d`.

**Early stopping:** Training stops when test loss hasn’t improved by
more than `tolerance` for `tol_window` consecutive epochs. The best-loss
embedding (not the final-epoch embedding) is returned. A final summary
line is always printed: `[early stop]` or `[max epochs]`.

**Index convention:** Items use **zero-based** integer indices in
Python. R functions subtract 1 before passing to Python and add rownames
back to the returned matrices.

------------------------------------------------------------------------

## Data objects

- `icon_triplets` — named list of 6 participant data frames; columns
  include `Center`, `Left`, `Right`, `Answer`, `sampleSet`, `sampleAlg`,
  `worker_id`
- `icon_pics` — list of PNG raster images for the 32 icon stimuli
- `icon_items` — data frame of the 32 icon item codes + stimulus file
  paths. There is no separate `icon_labels` object (a prior version of
  this doc claimed one existed) — item names/codes double as labels.
  Codes are 5 letters: face/place, day/night, female/male (faces) or
  church/house (places), old/young (faces) or new/old (places),
  black/white (faces) or big/small (places) — e.g. gender for
  classifier-evaluation examples is position 3 (`f`/`m`) of face (`f*`)
  items only.
- `icon_emb_ind` — named list of 6 per-participant 3D embeddings of the
  32 icon stimuli (each a 32 x 3 data frame, `dim_0`/`dim_1`/`dim_2`
  columns, rownames = item codes).
- `icon_emb_group` — single 32 x 3 data frame: 3D group embedding of the
  icon stimuli, same shape/convention as `icon_emb_ind` (item-code
  rownames, `dim_0`/`dim_1`/`dim_2` only). Regenerated 2026-09-23 (see
  “Recently added” below) — previously carried the raw CSV’s
  `worker_id`/`item`/`path` columns and generic integer rownames,
  inconsistent with every other embedding object in the package.
- `emotion_triplet_embedding` — 4D triplet-based embedding of 213 Shaver
  et al. (1987) emotion words (213 x 4 data frame, rownames = words)
- `emotion_bge_embedding` — BAAI/bge-m3 language-model embedding of the
  same 213 words, rotated onto its own lossless top-212 principal
  components rather than shipping the raw 1024 dims (213 x 212 data
  frame, rownames = words) — see `data-raw/emotion_embeddings.R` for the
  derivation/verification
- `animal_adjacency_matrix` — 295 x 295 directed weighted verbal-fluency
  co-occurrence graph over animal words (Wisconsin Longitudinal Study,
  min-5-participant threshold); contains all 213 items in
  `animal_triplet_embedding` plus 82 extra words (superordinate
  terms/synonyms/other species)
- `animal_triplet_embedding` — 6D triplet-based embedding of the 213
  animal words also present in `animal_adjacency_matrix` (213 x 6 data
  frame, rownames = words) — see `data-raw/animal_embeddings.R`. When
  comparing successor-representation distances to this embedding,
  compute
  [`successor_matrix()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/successor_matrix.md)
  on the full 295-word graph first and restrict to these 213 items
  afterward (see the `animal_adjacency_matrix` roxygen `@details` for
  why)
- `emotion_categories` — Shaver et al. (1987) basic-emotion category for
  each of the 213 `emotion_triplet_embedding`/`emotion_bge_embedding`
  words (213 x 1 data frame, rownames = words, one factor column
  `category`). Includes `"Absent"` (78 words, not assigned a category)
  and `"Surprise"` (3 words, too few for reliable CV) unfiltered — the
  recommended multinomial-classification subset drops both, leaving 132
  words across 5 categories (Anger 29, Fear 17, Joy 33, Love 16, Sadness
  37)
- `color_triplets` — named list of 46 participant data frames (same
  11-column shape as `icon_triplets`) from a triplet study on 58 color
  patches spanning color space; item codes
  (`Center`/`Left`/`Right`/`Answer`) are hex color strings, which double
  as plotting colors. Source: Zimnicki et al., CogSci poster
  (unpublished otherwise) — see the `color_triplets` roxygen `@source`
  for the link
- `color_emb_ind` — named list of 46 per-participant 3D embeddings of
  the 58 color patches (each 58 x 3, `dim_0`/`dim_1`/`dim_2` columns,
  rownames = hex color codes), fit the same way as `icon_emb_ind`
- `color_emb_group` — single 58 x 3 group embedding of the color
  patches, same shape/convention as `icon_emb_group`
- `color_lab` — 58 x 3 data frame of the same patches’ own CIE LAB
  coordinates (`l`/`a`/`b` columns, hex-code rownames) — not a fitted
  embedding, a reference point for how the triplet embedding relates to
  real perceptual color space. **Row order does not match
  `color_emb_group`/`color_emb_ind`** (confirmed directly, not assumed)
  — always re-index by rowname
  (e.g. `color_lab[rownames(color_emb_group), ]`) before any
  row-positional comparison
  (e.g. [`vegan::procrustes()`](https://vegandevs.github.io/vegan/reference/procrustes.html))

------------------------------------------------------------------------

## Conventions

- `devtools::document()` regenerates `man/` and `NAMESPACE` from
  roxygen2 tags
- [`pkgdown::build_site()`](https://pkgdown.r-lib.org/reference/build_site.html)
  rebuilds `docs/`; GitHub Actions auto-deploys `docs/` to GitHub Pages
  on push to main
- Never edit `man/*.Rd` files directly
- `embedding_vignette.Rmd`, `comparing_embeddings_vignette.Rmd`, and
  `condor_workflows_vignette.Rmd` set `eval = FALSE` globally
  (Python/Condor-dependent, no such step in pkgdown CI) — examples there
  are illustrative only. `overview_vignette.Rmd`,
  `read_data_vignette.Rmd`, and `tripletTools.Rmd` do **not** set a
  global `eval = FALSE` — their non-Python-dependent chunks actually
  execute during
  [`pkgdown::build_site()`](https://pkgdown.r-lib.org/reference/build_site.html)/`R CMD build`,
  working entirely from bundled example data; only genuinely Python- or
  external-file-dependent chunks are individually marked `eval = FALSE`
  within those three. (A prior version of this doc claimed
  `tripletTools.Rmd` was the *only* exception — wrong; corrected
  2026-09-23.)
- `sampleAlg == "check"` rows are attention-check trials; functions
  exclude them by checking `is.na(sampleSet)`
- **Adding a new vignette touches four places, not one**: the `.Rmd`
  itself, `README.md`’s vignette list, this file’s `Repository layout`
  section, and `_pkgdown.yml`’s
  `articles.contents`/`navbar.components.articles.menu` lists. Missing
  `_pkgdown.yml` is a hard build failure, not a cosmetic gap – pkgdown’s
  sitrep check aborts the whole site build if any vignette is missing
  from that explicit index (see the `trajectory_vignette.Rmd` bullet in
  “Recently added” for a real instance of this breaking the live GitHub
  Actions pkgdown build).

------------------------------------------------------------------------

## Recently added (v0.2.0)

- Full Python embedding pipeline under `inst/python/` using vendored
  `salmon` library
- [`setup_python_env()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/setup_python_env.md),
  [`train_embedding()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/train_embedding.md),
  [`run_group_embedding_from_list()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/run_group_embedding_from_list.md),
  [`run_embeddings_from_list()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/run_embeddings_from_list.md),
  [`run_embeddings()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/run_embeddings.md)
- [`estimate_dimensionality()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/estimate_dimensionality.md)
  — grid search over dimensionality with multiple random restarts and
  1-SE rule for `best_d` selection; parallel-ready via
  `future`/`future.apply`
- GPU/MPS/CPU device support threaded through the entire stack
- “Computing Triplet Embeddings” vignette covering setup, group
  embedding, individual embeddings, dimensionality selection, and
  parallel execution (multicore and HTCondor)
- Fixed pre-existing
  [`plot_cis()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/plot_cis.md)
  crash on single-member clusters
- Embedding-space comparison toolkit, ported in from standalone scripts
  and given roxygen docs + smoke tests:
  [`matrix_rank()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/matrix_rank.md),
  [`procrustes_rank_ceiling()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/procrustes_rank_ceiling.md),
  [`procrustes_spectral_ceiling()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/procrustes_spectral_ceiling.md),
  [`hellinger_dist()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/hellinger_dist.md),
  [`successor_matrix()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/successor_matrix.md),
  [`repeated_stratified_logistic_cv()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/repeated_stratified_logistic_cv.md).
  No new package dependencies — all base/`stats`.
- [`repeated_stratified_multinomial_cv()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/repeated_stratified_multinomial_cv.md)
  — sibling of
  [`repeated_stratified_logistic_cv()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/repeated_stratified_logistic_cv.md)
  for \>2-class labels; added as a separate function rather than
  extending the binary one, since generalizing its metrics to
  macro-averages would silently change `sensitivity`/`precision`/`f1`
  semantics for the already-shipped 2-class case. Backed by
  [`nnet::multinom()`](https://rdrr.io/pkg/nnet/man/multinom.html)
  (`nnet` added to Suggests — Recommended-priority, ships with R,
  effectively free).
- `emotion_triplet_embedding` / `emotion_bge_embedding` example
  datasets, plus fixed two stale `cfd36_*.csv` example paths (broken
  since the v0.2.0 CFD→icon data swap) and removed three orphaned,
  undocumented `cfd_*.rda` data files.
- `animal_adjacency_matrix` / `animal_triplet_embedding` example
  datasets, for the verbal-fluency/successor-representation vignette
  piece. Verified end-to-end:
  [`successor_matrix()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/successor_matrix.md)
  on the full graph → restrict to 213 matching items →
  [`hellinger_dist()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/hellinger_dist.md)
  → compared to the triplet embedding via
  [`vegan::procrustes()`](https://vegandevs.github.io/vegan/reference/procrustes.html)/[`procrustes_rank_ceiling()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/procrustes_rank_ceiling.md)/[`procrustes_spectral_ceiling()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/procrustes_spectral_ceiling.md).
  Considered sparse (`Matrix`-package) storage for the 88.7%-zero
  adjacency matrix but xz-compressed dense storage is already 13.8KB, so
  kept it a plain dense matrix.
- `emotion_categories` example dataset, giving
  [`repeated_stratified_multinomial_cv()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/repeated_stratified_multinomial_cv.md)
  a real-data example (132 words, 5 classes after dropping
  “Absent”/“Surprise”): accuracy 0.70, AUC 0.92. Along the way, found
  the function’s default `coefficient_warning = 10` (inherited from the
  binary function’s 2-class calibration) flags nearly every fold on real
  multinomial data (median max-coefficient 25.5 here) — not a bug, but a
  sign this threshold needs per-problem recalibration rather than blind
  trust in the default; a genuine outlier fold (coefficient 2291, from
  partial near-separation) is only distinguishable from the rest once
  recalibrated (9/60 flagged at threshold 50 vs 60/60 at the default
  10). Vignette will demonstrate this calibration process rather than
  just picking a better number silently. No function changes made.
- **`vignettes/comparing_embeddings_vignette.Rmd`** — “Comparing Triplet
  Embeddings to Alternative Representations,” written and committed.
  Three pieces, each with a real (not synthetic) worked example: (1)
  Procrustes alignment + rank/spectral ceilings on the emotion-word data
  (observed correlation 0.313 vs. ceilings of 0.436/0.418 — the triplet
  embedding captures ~72% of what’s achievable at its
  dimensionality); (2) classifier-based evaluation — binary:
  per-*individual* (not group) icon embeddings decoding face/place
  vs. day/night, showing a genuine crossover (4 participants encode
  category near-perfectly but not day/night; the other 2 the reverse) —
  multinomial: emotion categories (132 words, 5 classes), including the
  `coefficient_warning` recalibration story; (3) successor
  representations from the animal verbal-fluency graph, including why
  [`hellinger_dist()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/hellinger_dist.md)
  output is exactly (not approximately) Euclidean, and a
  gamma-sensitivity sweep.
- **Caught and fixed a real error while building the vignette:** the
  “observed Procrustes correlation” numbers used throughout this
  session’s validation work had been computed as `1 - sqrt(ss)` instead
  of the correct `sqrt(1 - ss)`
  ([`get.rep.dist()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/get.rep.dist.md)’s
  own convention: its output is a *distance*, `1 - sqrt(1-ss)`, so the
  correlation is `1 - distance = sqrt(1-ss)`, not `1 - sqrt(ss)`).
  Verified the fix two ways: it now matches `1 - get.rep.dist()`’s
  output exactly, and stays ≤ the theoretical ceiling (the wrong
  formula’s numbers happened not to violate that by coincidence, but
  were still the wrong quantity being compared). Nothing shipped (R/,
  man/, committed data) was affected — only conversational claims and
  one commit message (not rewritten). If citing correlation numbers from
  this package’s git history/commit messages predating this fix,
  recompute rather than trust them at face value.
- **`vignettes/tripletTools.Rmd`** (“Get Started” guide) and a refreshed
  `README.md` landing page — see the `Repository layout` section above
  for why this vignette’s filename matters and why it’s the one
  exception to the eval=FALSE convention. Every vignette URL in the
  README was verified against a real local
  [`pkgdown::build_site()`](https://pkgdown.r-lib.org/reference/build_site.html)
  run (isolated temp library), not just assumed. Surfaced but did not
  fix a pre-existing, unrelated pkgdown accessibility warning:
  `overview_vignette.Rmd`’s `vmat-mean-1.png` figure is missing alt
  text.
- Two useful
  [`successor_matrix()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/successor_matrix.md)/`gamma`
  facts worth remembering if this comes up again: (1) `gamma = 1` is
  disallowed and shouldn’t be approximated by `gamma` near 1 either —
  every row of `S` converges to the same shared stationary distribution
  as `gamma→1`, so per-item Hellinger distances collapse toward zero
  (verified: mean pairwise distance on the animal graph drops from 0.78
  at `gamma=0.5` to 0.002 at `gamma=0.9999`) — there’s nothing per-item
  left to compare once you’re near stationarity. (2) Low `gamma`
  approximates the **identity matrix**, not the transition matrix `P` —
  `S` is a geometric-weighted mixture of `I, P, P², …` where the `I`
  (t=0) term always carries the single largest weight for any
  `gamma < 1`, so `P` only ever enters as the first-order Taylor
  direction `S ≈ I + gamma(P-I)`, never as an intermediate regime `S`
  resembles (verified on the animal graph: `S` stays closer to `I` than
  to `P` until `gamma` is well past 0.5).
- [`find_discriminating_triplets()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/find_discriminating_triplets.md)
  — given two embeddings of the same items, finds triplets where the two
  make discrepant CKL predictions (symmetric KL divergence between each
  embedding’s CKL win-probability), for designing a follow-up study to
  test which embedding better matches human judgments. Candidate
  triplets are sampled (half uniform, half weighted by each item’s
  discrepancy), not enumerated exhaustively. Supports `max_per_item` to
  cap how often one item can dominate the returned set (greedy
  selection, descending discrepancy); this surfaced and fixed a real bug
  where the greedy loop was padding remaining slots with
  zero-discrepancy (i.e. non-discriminating) filler triplets once the
  cap was hit, rather than stopping short and warning.
  - **Weighting scheme replaced with the
    [`find_discrepant_items()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/find_discrepant_items.md)
    approach** (distance-profile Spearman correlation) after the user
    asked whether that newer function’s finding generalized here — it
    does: on the same single-relocated-item synthetic test, the original
    Procrustes-alignment-residual weighting ranked the true outlier only
    3rd, with a weight barely distinguishable from the top (wrong) item,
    while the Spearman-based weight ranks it 1st with more than 3x the
    runner-up’s weight. Reuses the squared distance matrices already
    computed for CKL scoring (squaring preserves rank order for
    non-negative distances, so no extra computation is needed for the
    Spearman correlation). The 50/50 uniform/weighted split itself was
    kept unchanged — the new weighting doesn’t share the old failure
    mode, but the uniform half is still a cheap general hedge against
    any remaining imperfection in the heuristic. One real bug caught
    while making this change: when the two embeddings are identical,
    every item’s discrepancy is exactly zero (not just near-zero, unlike
    the old Procrustes residuals, which had nonzero floating-point
    jitter from the alignment optimization even in this case), which
    zeroed out every sampling weight and crashed
    [`sample.int()`](https://rdrr.io/r/base/sample.html) — fixed by
    adding a small absolute floor (`1e-8`) alongside the existing floor
    that scales with the mean discrepancy.
- [`group_difference_test()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/group_difference_test.md)
  (local R function) + `inst/condor/condor_group_diff_workflow.py` (its
  Condor-scale companion) — permutation test for whether two participant
  groups’ embeddings differ reliably: fit each true group’s embedding,
  measure their Procrustes correlation via
  [`get.rep.dist()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/get.rep.dist.md),
  and compare that to a null distribution built from many random
  re-partitions of the pooled participants, **matched to the true
  groups’ sizes** (not a blanket 50/50 split — embedding quality depends
  on how much data went in, so an unequal true split compared against
  even halves would confound sample size with genuine group difference).
  One-sided p-value: proportion of null draws at or below the observed
  correlation. `d` is fixed across every replicate (chosen beforehand,
  e.g. via
  [`estimate_dimensionality()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/estimate_dimensionality.md)),
  never re-selected per permutation. The Condor workflow mirrors
  `condor_workflow.py`’s two-stage design (fit stage: one job per
  (replicate, side); compare stage: one job per replicate, run only
  after every fit completes) and is self-contained by design (duplicates
  `condor_workflow.py`’s small generic submit-file helpers rather than
  sharing a module between the two orchestrators).
  - **Two real bugs caught while testing this, both worth remembering as
    general gotchas:** (1) in the R function,
    [`as.character()`](https://rdrr.io/r/base/character.html) on a named
    vector **drops its names** —
    `group_vec <- as.character(group_vec[worker_ids])` silently produced
    an unnamed vector, making `names(group_vec)` `NULL` downstream and
    `triplet_list[ids]` resolve to an empty list, which only surfaced
    many calls later as an obscure `seq_len(split_idx)` error deep
    inside
    [`run_group_embedding_from_list()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/run_group_embedding_from_list.md)’s
    70/30 fallback path — always re-attach names explicitly after
    [`as.character()`](https://rdrr.io/r/base/character.html) on
    anything you intend to keep named. (2) in the Python orchestrator’s
    compare stage, the same variable was initially used for both
    `transfer_input_files` (needs the path *on the submit node*,
    e.g. `../stage1_fit/embedding_repN_sideA.csv`) and `arguments`
    (needs the bare filename the file lands under *inside the job’s
    sandbox* post-transfer, since HTCondor strips directory components)
    — these must be two separate `queue ... from (...)` variables
    (`*_src` vs. `*_name`), confirmed by cross-checking
    `condor_workflow.py`’s existing, correct pattern (`data_path` for
    transfer vs. `data_path.name` for arguments).
- `inst/condor/README_group_diff.md` — CHTC deployment steps for
  `condor_group_diff_workflow.py`. Written after the user’s own
  recollection of the deploy steps had two real gaps worth
  remembering: (1) this workflow needs **two** R scripts
  (`condor_group_fit.R` + `condor_group_compare.R`, both required in the
  same directory as the orchestrator, since it locates them relative to
  its own file path) — easy to under-count as “one” by analogy to the
  other workflow’s single `condor_fit.R`; (2) the two required data
  inputs are a **raw combined triplet-judgment CSV** plus a group-labels
  CSV — not precomputed embeddings, since the whole point of the
  workflow is fitting embeddings itself once per (replicate, side).
- **Real production bug found during an actual CHTC deployment** (627
  participants, `n_permutations=999`): `condor_group_diff_workflow.py`’s
  `write_filtered_csv()` re-scanned the *entire* triplet dataset once
  per (replicate, side) output file — O(n_replicates × total_rows) —
  which stalled the driver silently (no error, just nothing ever
  reaching `condor_q`) long before its first `condor_submit` call. Fixed
  by grouping rows by `worker_id` once up front
  (`group_rows_by_worker()`), plus trimming every output file to just
  the 6 columns
  [`run_group_embedding_from_list()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/run_group_embedding_from_list.md)
  actually reads (real triplet exports often carry several more that
  were being needlessly rewritten into every one of thousands of output
  files). Benchmarked on synthetic data sized like the real deployment:
  ~16.8 → ~11.7 minutes for the full 2000-file run. Important caveat
  that surfaced from this benchmark: the sheer *volume* of data written
  (each output file holds close to half the full dataset) is itself a
  substantial, roughly-linear cost that persists even after fixing the
  quadratic scan — if this remains too slow in practice, the more
  substantial fix is having each Condor job filter its own data in R
  inside the container, rather than pre-splitting into thousands of
  files on the submit node.
- [`find_discrepant_items()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/find_discrepant_items.md)
  — ranks items by how much their distance-to-others profile differs
  between two embeddings (Spearman correlation, per item, between that
  item’s row of each embedding’s own distance matrix). Alignment-free by
  construction (Euclidean distance is already
  rotation/reflection/translation-invariant, and each item’s score
  depends only on its own distances, not a shared fit), so it works
  directly across different-dimensional embeddings and sidesteps
  [`find_discriminating_triplets()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/find_discriminating_triplets.md)’s
  Procrustes-residual outlier-distortion problem entirely. **Must use
  `method = "spearman"`, not `"pearson"`** — verified on the same
  single-relocated-item synthetic test used for the
  Procrustes/[`find_discriminating_triplets()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/find_discriminating_triplets.md)
  findings above: Pearson correlation ranked the true outlier *outside
  the bottom 5 entirely*, because moving one item corrupts one distance
  entry in every other item’s profile too, and Pearson is highly
  sensitive to a single extreme value even when the rest of the profile
  is untouched. Spearman (rank-based, so one extreme value gets
  compressed rather than dominating) correctly and decisively ranked the
  true outlier first, with every other item’s correlation far higher —
  confirmed this isn’t a degenerate default by also checking two
  genuinely independent embeddings, where Spearman correlations spread
  sensibly around 0 with no artificial pattern.
- **`condor_individual_embeddings_workflow.py`** (+
  `condor_individual_fit.R`,
  `individual_embeddings_params_template.yml`,
  `README_individual_embeddings.md`) — third, independent Condor
  workflow: fits a separate embedding for each unique `worker_id` in a
  combined triplet CSV (one Condor job per participant, no
  true/null-permutation machinery needed since there’s no comparison
  step), then concatenates every result into a single `embeddings.csv`
  indexed by `worker_id` and `item`. The large-scale companion to
  [`run_embeddings_from_list()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/run_embeddings_from_list.md)’s
  per-individual output, for when fitting every participant locally
  (even multicore via `future`/`future.apply`) would take too long.
  Single-stage design (fit, then a local, non-Condor concatenation step)
  since there’s nothing to compare across workers, unlike
  `condor_group_diff_workflow.py`’s two-stage fit-then-compare shape.
  Reuses `condor_group_diff_workflow.py`’s
  `HARD_REQUIRED_COLUMNS`/`SOFT_REQUIRED_COLUMNS` trimming and
  per-worker row-grouping approach (same rationale: avoid rewriting
  every unused column, and avoid an O(n_workers × total_rows) rescan)
  but does not share code with it directly — self-contained by the same
  design choice as the other two workflows. Per-worker files are indexed
  by job position (`worker0.csv`, `worker1.csv`, …), not by the raw
  `worker_id` string, so an arbitrary `worker_id` never has to be
  filesystem-safe; a check that no `worker_id` contains a comma guards
  the one place it *does* get embedded literally (the Condor
  `queue ... from (...)` block). The per-job R script
  (`condor_individual_fit.R`) cross-checks that its `--triplet_data`
  file contains only the one `--worker_id` it was told to expect,
  failing loudly on any orchestrator/filtering bug rather than silently
  tagging a fit with the wrong participant’s ID – verified this guard
  actually fires, and separately smoke-tested the whole per-job script
  end-to-end on one real `icon_triplets` participant.
- [`reduce_embedding_dimension()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/reduce_embedding_dimension.md)
  — companion to the per-participant Condor workflow above: rather than
  running a full per-participant dimensionality search (expensive to
  repeat hundreds of times on Condor), fit every participant at one
  shared, generously high `d_max` locally on the submit node, then
  reduce each one’s own fitted embedding down afterward via PCA
  ([`base::svd()`](https://rdrr.io/r/base/svd.html) on the centered
  coordinates), keeping the smallest number of leading principal
  components whose cumulative variance meets a threshold (default 0.95).
  PCA rather than classical MDS: since the embedding is already a set of
  exact Euclidean coordinates, MDS’s eigendecomposition of the
  double-centered distance Gram matrix is provably identical (up to
  rotation) to PCA on the coordinates directly, so MDS would just be a
  more expensive detour through an unnecessary n×n distance matrix to
  the same answer. Also reports triplet-prediction accuracy of the
  reduced embedding vs. the original full-dimension one (and a per-k
  `diagnostics` table of the whole curve), evaluated against *every*
  triplet the participant judged (train+test combined), not just their
  own held-out split — deliberately, since a held-out-only accuracy
  comparison would make the apparent “right” dimensionality partly an
  artifact of which triplets happened to land in that participant’s
  particular random split (a real concern the user raised), whereas the
  truncation step itself is unsupervised (never looks at triplet
  labels), so there’s no leakage in scoring it against the full dataset.
  Verified on a synthetic embedding with 2 true dimensions + 3 near-flat
  noise dimensions (correctly recovers `k=2`) and smoke-tested on a real
  `icon_triplets` participant fit at `d=8` (variance concentrated in the
  first 2 dimensions at 97%, reduced-embedding accuracy 0.909
  vs. full-embedding accuracy 0.918).
- **`vignettes/condor_workflows_vignette.Rmd`** — new vignette
  consolidating HTCondor deployment docs for all three `inst/condor/`
  workflows, which had been scattered (dimensionality-search workflow
  documented inline at the end of `embedding_vignette.Rmd`; the other
  two only in their own `README_*.md` files, with no vignette coverage
  at all). Removed the “HTCondor cluster” / “Building and publishing the
  container image” / “An end-to-end Condor workflow” sections from
  `embedding_vignette.Rmd` (which now just points here), keeping only
  the `future`/`plan()`-based local-multicore content there, since
  that’s a genuinely different mechanism from the Condor workflows. Also
  documents a per-analysis **sparse git clone** of just `inst/condor/`
  (`--filter=blob:none` partial clone + cone-mode `sparse-checkout`) as
  the recommended way to get the workflow scripts onto a submit node —
  arrived at after the user asked whether the files could live on a
  search path instead of being copied per run: a plain shallow clone
  still checks out the package’s *entire* source tree (shallow only
  trims history, not which files exist), so sparse-checkout is what
  actually avoids pulling everything else, while still leaving a real
  git repo behind for provenance (`git log -1`) — preferred over
  manually copying 2-3 loose files, which carries no record of which
  commit produced them, and over one long-lived shared clone, which
  risks a two-stage workflow’s later stage silently running under
  different code than its earlier stage if someone `git pull`s in
  between. The vignette’s “Troubleshooting a job that seems stuck”
  section captures a real live debugging session from this same day:
  `condor_q`’s `RemoteUserCpu`/`JobStatus` fields lag behind actual job
  state (periodic schedd updates, not a live feed) and can look
  identically “stalled” whether a job is genuinely hung, merely
  suspended under CPU contention on a shared execute slot, or just a
  slow-but-healthy outlier — `condor_ssh_to_job` (with its harmless
  `groups: cannot find name for group ID` login noise) plus `ps aux`’s
  `%CPU`/`STAT` columns is the only way to tell them apart directly; in
  the actual case that prompted this, a job showing flat `RemoteUserCpu`
  after 3+ hours turned out to be genuinely computing (98% CPU, STAT
  `Rl`), just slower than its siblings, not stuck at all. Recommends
  `condor_vacate_job` (keeps the job’s own ID, so an orchestrator’s
  blocking `condor_wait` needs no special handling) over `condor_rm` +
  manual resubmission (a new job ID, with unclear interaction with
  `condor_wait`’s handling of a removed rather than terminated job) as
  the first move for a job that really is stuck.
- **Real production bug found live during the CHTC group-difference run
  described above, distinct from the “job looks stalled” issue**:
  `condor_group_diff_workflow.py`‘s Stage 2 came back with roughly half
  of 101 comparison jobs reporting `Normal termination (return value 0)`
  and an empty `.err`, yet an empty or missing `compare_N.csv` output. A
  clean exit + empty stderr rules out a script bug (`Rscript` exits 1 by
  default on any uncaught R error), pointing instead at HTCondor’s
  output-transfer path getting overloaded when ~100 jobs finish within
  the same narrow window. Fixed with a new shared
  `submit_jobs_with_retry()` helper — duplicated (by the established
  self-contained-per-workflow convention) into all **three**
  orchestrators, not just the one that broke, since all three submit
  many same-shaped jobs the same way and share the identical exposure:
  verifies every job’s expected output file after `condor_wait` returns
  and automatically resubmits just the missing/empty ones (up to 5
  attempts) before failing with a clear error naming exactly which jobs
  never produced valid output, replacing what used to be a bare,
  unhelpful `StopIteration` traceback. Also added an optional
  `condor.batch_size` config field (all three `*_params_template.yml`)
  that submits jobs in sequential chunks instead of all at once,
  directly capping how large a simultaneous-completion burst can be
  rather than just cleaning up after one. `condor_workflow.py`’s two
  multi-job stages needed one additional fix to support retrying a
  subset safely: their result files were named by Condor’s own
  `$(Process)` number, which is reassigned from 0 on every new
  submission — resubmitting only the missing jobs would have overwritten
  already-good low-numbered results with different jobs’ output. Fixed
  by giving every job a stable `job_index` field (assigned once, up
  front, independent of Condor’s own per-submission numbering) and
  naming outputs by that instead. Live-verified the diagnosis is correct
  (not a data/logic bug) by writing a same-session local-R recovery
  script that recomputes Stage 2 entirely outside Condor, straight from
  the already-good Stage 1 embeddings — confirms these comparisons are
  cheap enough that distributing them via Condor was never necessary for
  the wall-clock savings, only convenient, which is why it’s now
  documented as the recommended fallback (in
  [`vignette("condor_workflows_vignette")`](https://knowledge-and-concepts-lab.github.io/tripletTools/articles/condor_workflows_vignette.md))
  when retries are exhausted rather than something to keep fighting the
  transfer path over.
- **Documentation audit (2026-09-23)**, prompted by the user noticing
  `overview_vignette.Rmd` claiming the package “does not… compute
  embeddings” (stale since the v0.2.0 embedding pipeline shipped) and
  the Getting Started guide treating `icon_emb_group` as if item labels
  were a column rather than row names. Systematic pass found and fixed
  five discrepancies: (1) that stale capability claim; (2)
  `icon_emb_ind`’s roxygen `@format` describing the raw 6-column CSV
  shape rather than the actual shipped 3-column object; (3)
  `icon_emb_group` itself — not just its docs — inconsistent with every
  other embedding object’s rownames convention (see “Data objects”
  above; fixed by cleaning `data-raw/icon_embeddings.R` the same way as
  `icon_emb_ind` and regenerating, which let three separate
  `rownames(emb) <- emb$item`/`[,1:3]` workarounds in
  `tripletTools.Rmd`, README, and `overview_vignette.Rmd` be simplified
  away); (4) `get_combined()` vs. the actual
  [`get.combined()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/get.combined.md)
  (dot, not underscore) — a real typo in `read_data_vignette.Rmd` prose
  and three roxygen files, inconsistent with the correctly-dotted
  working `\link{}` cross-references elsewhere; (5) a missing `fig.cap`
  (accessibility) on one `overview_vignette.Rmd` chunk, already known
  but never fixed. Also surfaced, while auditing: 52 exported functions
  cross-referenced against all vignette prose turned up several with
  real functionality and zero narrative coverage
  ([`test_for_clusters()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/test_for_clusters.md),
  [`find_discrepant_items()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/find_discrepant_items.md)/[`find_discriminating_triplets()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/find_discriminating_triplets.md)
  as a pair,
  [`summarize_dimensionality()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/summarize_dimensionality.md)/[`summarize_learning_curve()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/summarize_learning_curve.md),
  [`plot_directions()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/plot_directions.md),
  [`get.nearest.k()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/get.nearest.k.md),
  [`run_embeddings()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/run_embeddings.md))
  —
  [`test_for_clusters()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/test_for_clusters.md)
  and
  [`summarize_dimensionality()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/summarize_dimensionality.md)/[`summarize_learning_curve()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/summarize_learning_curve.md)
  now addressed (see the two bullets below); the rest still open.
  [`get.rep.dist()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/get.rep.dist.md)
  never propagates `names(elist)` into its output matrix’s dimnames
  (confirmed while writing a follow-up simulation script), a minor
  usability gap not yet fixed.
- **[`test_for_clusters()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/test_for_clusters.md)
  had a real, undiscovered statistical bug, found while investigating
  why it failed to detect known real clustering.** The user had built a
  12-participant dataset (their own icon-triplet judgments, replicated
  with 5% of trial answers flipped per twin) with *verified*
  ground-truth 2-group structure (confirmed via
  [`cutree()`](https://rdrr.io/r/stats/cutree.html) recovering the exact
  expected split and each twin pairing with its own parent) — yet
  `hopkins_p_value` stayed solidly non-significant (~0.3-0.9) regardless
  of sample size. A calibrated synthetic power simulation (noisy
  replicates of two real archetype embeddings, matched to the observed
  real effect size) showed **Hopkins power was exactly 0 at n=12/24/48
  and only jumped to 1.0 at n=96** — the smoking gun, since real power
  should improve smoothly with n, not stay at exactly zero across a 4x
  range. Root cause: the function’s dimensionality-reduction step
  retained every numerically-positive-eigenvalue cMDS dimension (via the
  same tolerance convention as
  [`matrix_rank()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/matrix_rank.md)),
  and with realistic continuous per-participant noise this retains
  essentially `n - 2` dimensions almost regardless of how many
  dimensions carry real signal — confirmed directly (`k_use` tracked
  `n-2` almost exactly at every simulated n) — which is close to the
  most adversarial possible condition for a nearest-neighbor statistic
  like Hopkins. Forcing a small `k` manually made things *worse* at
  first, which exposed a **second, independent bug**: `u` (real-to-real
  nearest-neighbor distance) was computed from the original, untruncated
  distance matrix, while `w` (synthetic-to-real) was computed from
  Euclidean distance in the truncated coordinate space — any truncation
  silently deflated `w` relative to `u` as a pure artifact, regardless
  of whether the dropped dimensions were signal or noise. Fixed both:
  added
  [`estimate_intrinsic_dimension()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/estimate_intrinsic_dimension.md)
  (Horn’s parallel analysis on the cMDS decomposition —
  permutation-testing each dimension’s eigenvalue against
  column-permuted null data, not a numerical-precision tolerance) as
  [`test_for_clusters()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/test_for_clusters.md)’s
  new `k_use` default when not supplied directly, and recomputed `u`
  within the same `k_use`-dimensional space as `w`. The decision rule
  for how many leading dimensions to keep needed two iterations: “stop
  at the first threshold failure” is vulnerable to Horn’s
  well-documented rank-1 conservatism (the top eigenvalue’s null
  threshold is itself an inflated order statistic, confirmed stable
  across n_permutations 100-2000, so more permutations alone didn’t fix
  it); “keep every dimension that ever passes” over-corrected into a
  multiple-comparisons problem (a single chance false positive at any
  high rank inflated `k` to the full candidate pool on pure-noise test
  data). Settled on “stop after two *consecutive* failures,” verified
  against a purpose-built synthetic test suite
  (`tests/testthat/test-estimate_intrinsic_dimension.R`) including two
  informative test-writing mistakes worth remembering: a single
  unstructured Gaussian cloud has geometric rank 2 but *no* real
  cross-dimensional structure (correctly estimates k=1, not 2 — parallel
  analysis measures structure beyond noise, not
  [`matrix_rank()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/matrix_rank.md)-style
  numerical rank), and a clean 2-cluster split needs only 1 real
  discriminant dimension even though the data lives in 2D (a general
  discriminant-analysis fact: G groups need at most G-1 dimensions to
  separate). After the fix: the original *un-augmented* 6-participant
  real dataset newly detects its real clustering too (p=0.025,
  previously never significant), the 12-participant dataset’s Hopkins
  p-value dropped to 1e-6-1e-9 across seeds with `best_g=2` every time,
  and the recalibrated power simulation went from (0.00, 0.00, 0.00,
  1.00) to (1.00, 1.00, 1.00, 1.00) at n=(12,24,48,96) — full power
  restored at every tested sample size, not just the one specific
  dataset used for diagnosis.
- **[`test_for_clusters()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/test_for_clusters.md)
  illustrated in `overview_vignette.Rmd`**, new “Is there real cluster
  structure?” subsection slotted right before the existing `cutree(k=2)`
  step it’s meant to inform. Deliberately uses the bundled 6-participant
  `icon_emb_ind` data rather than bundling the 12-participant augmented
  dataset from the bug-hunt above – checked Hopkins p-value stability
  across 20 seeds first (ranges 0.005-0.34, ~75% below 0.05, `hopkins`
  statistic itself consistently \>0.5 even on the non-significant draws)
  and picked `seed = 3` (p = 0.0054) for a comfortably significant,
  reproducible example, while the prose is explicit that small-n results
  are naturally noisier run to run rather than hiding it. Left
  `best_g = 3` (doesn’t match the true 2 groups) in rather than
  cherry-picking around it, since it’s a live demonstration of the
  function’s own documented “trust Hopkins over BIC at small n”
  guidance. Needed `Config/Needs/website: mclust` added to `DESCRIPTION`
  plus a defensive `eval = requireNamespace("mclust", quietly = TRUE)`
  on the chunk, since `overview_vignette.Rmd`’s chunks actually execute
  during the real pkgdown build (see the `eval = FALSE` correction
  above) and `mclust` is Suggests-only.
- **[`summarize_dimensionality()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/summarize_dimensionality.md)/[`summarize_learning_curve()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/summarize_learning_curve.md)
  illustrated in `condor_workflows_vignette.Rmd`**, new “Recomputing a
  summary yourself, without refitting anything” subsection in
  Workflow 1. The real gap wasn’t “how do you get from Condor output to
  a decision” – `condor_workflow.py`’s orchestrator already
  auto-aggregates into
  `dimensionality_summary.csv`/`learning_curve_summary.csv` during a
  normal run – it’s “how do you redo that aggregation yourself” (the
  orchestrator’s own aggregation step hitting the exact output-transfer
  failure mode documented two sections earlier in the same vignette, or
  wanting to try a different `best_d_norm_penalty` post-hoc without
  re-fitting). Confirmed both functions are exactly
  [`estimate_dimensionality()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/estimate_dimensionality.md)/[`estimate_learning_curve()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/estimate_learning_curve.md)’s
  own internal aggregation logic, factored out (traced the call sites
  directly in
  `R/estimate_dimensionality.R`/`R/estimate_learning_curve.R`), and that
  both operate on a plain data frame matching `condor_fit.R`’s real
  per-job CSV columns – so the example needed no bundled data at all,
  just a small constructed `results` data frame built to the same shape.
  Took a bit of tuning to get a clean illustrative `best_d`: an initial
  version’s plateau (d=3/4/5 losses close but not equal) let `best_d`
  land on 5 rather than the intended 3, since the one-SE band was
  narrower than the gap; flattening d=3/4/5 to genuinely equal true loss
  and sweeping seeds for a clean result fixed it (`seed = 2`). Verified
  by actually rendering both vignettes end-to-end via
  [`rmarkdown::render()`](https://pkgs.rstudio.com/rmarkdown/reference/render.html)
  (this vignette’s chunks are `eval = FALSE`, so this was the only way
  to confirm the code is actually correct, not just plausible-looking)
  and confirming the new internal anchor link resolves in the rendered
  HTML.
- **[`find_discrepant_items()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/find_discrepant_items.md)/[`find_discriminating_triplets()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/find_discriminating_triplets.md)
  illustrated in `comparing_embeddings_vignette.Rmd`**, new “Finding
  where two embeddings disagree” section slotted right after the
  Procrustes-ceiling section, using the already-bundled
  `emotion_triplet_embedding` (4D) and `emotion_bge_embedding`
  (effectively-212D) — no new data needed. The user’s original plan was
  to cMDS-reduce the BGE embedding to 4D first to match dimensionality;
  checking the actual R source (not just the CLAUDE.md summary of it)
  confirmed this is unnecessary and would have undercut the point: both
  functions are explicitly alignment-free by construction (distances
  computed within each embedding’s own native space, no shared
  fit/padding step), so mismatched dimensionality was never a problem to
  begin with – that’s one of their headline properties, not an obstacle.
  The section leans into this directly, contrasting it with the
  Procrustes section just above (which *does* need to handle the
  dimensionality mismatch explicitly). Real results on the bundled data
  are genuinely interpretable: most-discrepant items include several
  high-arousal/blended-affect words (`arousal`, `startle`, `alertness`,
  `titillation`), and the top discriminating triplet (`happiness`:
  `glee` vs. `frustration`) is concrete enough a reader can see exactly
  what a follow-up participant judgment would settle. All printed
  numbers verified against real function output (one manual rounding
  slip caught and fixed: `mirth`’s correlation is 0.0828, not 0.0829).
  Also updated this vignette’s Overview and closing Summary tables to
  list the new section alongside the existing three.
- **[`run_embeddings()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/run_embeddings.md)
  decided not to need its own vignette section.** Confirmed via source
  (not just this doc’s own prior, imprecise summary) that
  [`run_embeddings_from_list()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/run_embeddings_from_list.md)
  really does call it internally, but they’re not just “same thing,
  different input”:
  [`run_embeddings()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/run_embeddings.md)’s
  `input_file` must already be pre-indexed integer CSV
  (`head`/`winner`/`loser`), not the standard
  `Center`/`Left`/`Right`/`Answer` string format everything else in the
  package uses, and it returns a flat data frame rather than the
  `individual`/`group` named-list shape. Real use case is narrow (large
  datasets or an external pipeline already producing pre-indexed CSVs,
  avoiding a pointless load-into-R-then-write-back-out round trip) –
  added a one-paragraph pointer in `embedding_vignette.Rmd`’s
  individual-embeddings section rather than a dedicated example. Also
  fixed this file’s own function-inventory table, which said
  [`run_embeddings()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/run_embeddings.md)
  was “called by the above” (plural) – only true for
  [`run_embeddings_from_list()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/run_embeddings_from_list.md);
  [`run_group_embedding_from_list()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/run_group_embedding_from_list.md)
  calls
  [`train_embedding()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/train_embedding.md)
  directly and never touches it.
- **[`get.nearest.k()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/get.nearest.k.md)
  illustrated in `overview_vignette.Rmd`**, new “Checking true nearest
  neighbors beyond 2 dimensions” subsection right after the existing 2-D
  [`plot_pics()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/plot_pics.md)
  scatter of `icon_emb_ind[[1]]` (which only shows 2 of that embedding’s
  3 dimensions). Checked empirically first: nearly every one of the 32
  icon items’ 2-D-vs-3-D nearest-neighbor sets differ; picked `pdcns` as
  the example since the effect is especially clean there – the apparent
  2-D nearest neighbor (`pncos`) isn’t even in the true top-5 once the
  third dimension is included. Also tightened
  [`get.nearest.k()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/get.nearest.k.md)’s
  own `@param dmat` roxygen, which said “Data matrix” (readable as raw
  embedding coordinates) when it actually requires a precomputed
  symmetric *distance* matrix – confirmed from the function’s own
  example, which computes [`dist()`](https://rdrr.io/r/stats/dist.html)
  first. **Caught and fixed a real mistake while writing this**: unlike
  the vignettes with global `eval = FALSE` (where a hand-typed `#> ...`
  block after a chunk is the correct pattern, since nothing actually
  runs), `overview_vignette.Rmd`’s chunks execute for real, so an
  initial hand-typed output block duplicated the chunk’s own real,
  auto-printed output in the rendered page – caught by actually
  rendering and reading the HTML, not just checking the source looked
  right, and removed.
- **[`test_for_clusters()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/test_for_clusters.md)
  now also returns `model_name`/`classification`** – the BIC-winning
  covariance-structure model (e.g. `"EII"`, `"VVV"`) at `best_g`, and
  that model’s own MAP hard cluster assignment, printed (`model_name`
  only, not the classification vector) and returned invisibly alongside
  the existing fields. Motivated by a user design question: given the
  package’s usual downstream step is `hclust(..., method="ward.D")` +
  [`cutree()`](https://rdrr.io/r/stats/cutree.html) rather than mclust’s
  own assignment, should the two be unified? Landed on: expose both so
  users can directly compare a `hclust`-based partition against the
  winning GMM’s own assignment (a winning model far from `"EII"`/`"VII"`
  – roughly spherical, equal-volume – explains a low silhouette score at
  the BIC-recommended k as a method-assumption mismatch rather than a
  wrong partition) without making the package pick one as authoritative,
  given the already-documented small-n BIC fragility (see the bug entry
  above) argues against trusting the full 14-model search for the actual
  grouping decision. Implementation reuses `bic_mat` directly
  (`mclust::Mclust(coords, x = bic_mat)`) rather than recomputing BIC,
  so `model_name`/`classification` are guaranteed consistent with
  `best_g`. **Real bug caught while adding this**:
  `mclust::Mclust(data, x = bic_mat)` internally re-evaluates a stored
  call to `mclustBIC()` *unqualified* – this only resolves if the
  `mclust` namespace is attached to the search path;
  [`requireNamespace("mclust", quietly = TRUE)`](https://rdrr.io/r/base/ns-load.html)
  (this package’s usual Suggests convention, never
  [`library()`](https://rdrr.io/r/base/library.html)) is not enough,
  confirmed against a properly installed package (not just
  `devtools::load_all()`, which was ruled out as a possible confound
  first). Fixed by attaching `mclust` only for the duration of that one
  call ([`attachNamespace()`](https://rdrr.io/r/base/ns-load.html) +
  `on.exit(detach(...))`), and only if not already attached – avoids
  silently leaving `mclust` on the caller’s search path as a side effect
  of calling this function.
- **[`test_cluster_stability()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/test_cluster_stability.md)**
  – new function, companion to
  [`test_for_clusters()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/test_for_clusters.md),
  addressing a follow-up methodological question: is a
  hierarchical-clustering partition that “looks interpretable” actually
  trustworthy, especially when Hopkins/BIC/silhouette give mixed
  signals? Refits `hclust(method="ward.D")` + `cutree(k)` on many random
  subsamples (without replacement, default 80% of participants) and
  compares each resampled partition back to the full-data partition via
  [`mclust::adjustedRandIndex()`](https://mclust-org.github.io/mclust/reference/adjustedRandIndex.html)
  (mean/median `ari` across resamples), plus a per-participant
  `participant_stability` score (fraction of pairwise
  same-cluster-vs-different-cluster decisions, against every
  co-resampled participant, that agree with the full-data partition)
  flagging the least reproducibly-assigned individuals. Deliberately
  does *not* reduce to `k_use` cMDS dimensions first (unlike
  [`test_for_clusters()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/test_for_clusters.md))
  – it tests the partition users actually act on, which in this
  package’s own convention
  (`get_group_list_mean()`/[`pacc.by.cluster()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/pacc.by.cluster.md)
  examples) is `hclust` on the raw distance matrix directly, not a
  cMDS-reduced one. **Important documented limitation, found
  empirically, not assumed:** this tests whether *this specific finite
  sample’s* split survives resampling, not whether the population has
  real structure – on purely random, structure-free synthetic data
  during development, mean ARI averaged ~0.67 at n=20 and ~0.38 at n=60
  across independent draws (individual draws ranging ~0.2-0.85),
  i.e. far from the naively-expected ~0 “no stability” value, and worse
  at smaller n – directly echoing the already-documented small-n BIC
  false-positive pattern above. Ruled out this being a computation bug
  by checking real variability across 15 independent random draws (not a
  fixed inflated constant) and confirming a genuinely no-natural-split
  case (points evenly spaced on a circle) scores lower than typical
  random-Gaussian draws. Documented explicitly in the function’s roxygen
  (“What ‘stable’ does and doesn’t mean”) so a high `mean_ari` isn’t
  mistaken for population-level validation on its own – pair with a
  significant Hopkins result, and treat an external,
  independently-measured correlate of cluster membership as the
  strongest available validation.
- **[`estimate_intrinsic_dimension()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/estimate_intrinsic_dimension.md)’s
  “forced to 1” message improved to distinguish two very different
  situations it was previously conflating.** Prompted by a real,
  confusing case on a live dataset (36-stimulus Gabor-wavelet triplet
  task, orientation x contrast, individual embeddings compared via
  [`get.rep.dist()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/get.rep.dist.md)):
  the leading cMDS eigenvalue was clearly, visually dominant, yet
  [`estimate_intrinsic_dimension()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/estimate_intrinsic_dimension.md)
  reported “not even the leading dimension exceeded its permutation
  threshold” – read at face value, this sounds like “no structure at
  all,” which didn’t match the data. Root cause (confirmed via a
  parameter sweep that reproduced it in *every* combination tried, not a
  rare edge case): permutation preserves each column’s own variance
  exactly, only scrambling which participant has which value, so when
  nearly all real signal concentrates in one dimension, the permutation
  null’s own top eigenvalue ends up built largely from that same
  dominant variance – the leading dimension effectively has to “beat a
  shuffled version of itself,” a bar Horn’s parallel analysis is
  documented to handle poorly at rank 1 specifically, here severe enough
  to fail even an obvious true signal. Added `dominance_ratio` (leading
  eigenvalue / mean of the rest) and `forced_to_one` to the return
  value; when `forced_to_one` is `TRUE` and `dominance_ratio > 3`, the
  verbose message now explains this is likely a false negative rather
  than an absence of structure, and to corroborate with independent
  evidence (a reproducible `hclust` split, or
  [`test_for_clusters()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/test_for_clusters.md)’s
  BIC) rather than trusting the “k=1 forced” floor as a genuine
  non-detection. New test (`test-estimate_intrinsic_dimension.R`) locks
  down the exact failure mode: a single dominant dimension plus a few
  noise dimensions reliably triggers `forced_to_one = TRUE` with
  `dominance_ratio` in the 15-40x range across every `n`/`n_noise`/seed
  combination tried during development.
- **[`test_for_clusters()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/test_for_clusters.md)
  gained `report_classification_for`**, letting a caller also get the
  winning covariance model and MAP classification at a specific `G`
  other than `best_g` (e.g. a close runner-up), not just at the
  BIC-optimal one. Reuses the already-computed `bic_mat`
  (`mclust::Mclust(coords, G = g, x = bic_mat)`, confirmed to return the
  value already sitting in `bic_mat`’s own row for that `G`, not a fresh
  independent search), so a requested `G`’s `model_name` is always
  consistent with what the printed `bic` table already implies. Returned
  as `alt_classifications`, a named list (`"G=3"`, etc.), `NULL` when
  not requested. Motivated by a live finding on the Gabor-wavelet
  dataset above: `hclust`’s natural 2-way split isolates a small, tight,
  well-separated participant subgroup, but the GMM’s own `G=2` MAP
  assignment doesn’t match it – it makes a more balanced split instead.
  Forcing `G=3` via this new argument showed the GMM’s 3rd component
  subdivides the *large* group rather than isolating the small one,
  confirming (not just theorizing) that Gaussian-mixture BIC search and
  Ward’s linkage are optimizing genuinely different objectives here: a
  GMM with a spare component generally gains more likelihood by
  subdividing a dominant, numerically large mass than by dedicating a
  whole component to a small, tight minority – exactly where Ward’s
  excels and GMM/BIC struggles. Practical upshot for interpreting this
  class of dataset: don’t expect
  [`test_for_clusters()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/test_for_clusters.md)’s
  own classification/BIC search to reproduce a `hclust`-identified
  minority subgroup, even when both agree on the same best `G`.
- **[`generalized_procrustes()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/generalized_procrustes.md)**
  (new) +
  **[`smooth_embedding_trajectory()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/smooth_embedding_trajectory.md)**
  (new) – built after the same Gabor-wavelet investigation above
  concluded the representational distance matrix’s dominant single
  latent dimension plausibly reflects a genuine *continuum*
  (contrast-only strategy at one end, shifting through increasing use of
  orientation, not necessarily two or three discrete strategy clusters).
  The user’s own first-pass approach – bin participants along the 1-D
  cMDS axis into a few fixed-width bins, Procrustes-align and average
  each bin *separately* – has two rough edges this generalizes away:
  hard bin boundaries discard real position information, and
  independently-chosen per-bin alignments make bin-to-bin comparisons
  only loosely comparable.
  [`generalized_procrustes()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/generalized_procrustes.md)
  does iterative GPA (Gower, 1975): align every embedding in a list onto
  a running consensus, recompute the consensus, repeat to convergence,
  so *all* participants land in one shared frame simultaneously (unlike
  [`get.rep.dist()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/get.rep.dist.md)’s
  pairwise-only alignment).
  [`smooth_embedding_trajectory()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/smooth_embedding_trajectory.md)
  then takes a 1-D position per participant
  (e.g. `cmdscale(get.rep.dist(elist), k=1)`) and a grid of query
  points, and at each one computes a Gaussian- (or Epanechnikov-)
  kernel-weighted average of the GPA-aligned embeddings – a continuous
  version of the bin-and-average procedure, default bandwidth via
  [`stats::bw.nrd0()`](https://rdrr.io/r/stats/bandwidth.html) (same
  rule of thumb [`density()`](https://rdrr.io/r/stats/density.html)
  uses). Also returns Kish’s effective sample size
  (`(sum(w))^2 / sum(w^2)`) at each query point specifically to flag the
  boundary regions (fewest nearby participants, most exposed to being
  driven by one or two extreme individuals) – directly relevant to
  interpreting any trend or reversal found near either end of the axis.
  **Real bug caught and fixed during development, not just a design
  choice:** naive iterative GPA with `scale = TRUE` (rescaling each
  embedding to best match the *previous* iteration’s consensus, then
  re-averaging) is not scale-neutral – traced directly: the consensus’s
  sum of squares decayed *geometrically* toward exactly zero (~0.37x per
  iteration, verified on real `icon_emb_ind` data), never stabilizing,
  so every aligned embedding came out at ~1e-6 magnitude regardless of
  the actual data. Fixed by renormalizing the consensus to unit
  sum-of-squares after each iteration (standard practice in GPA,
  Gower 1975) – but *only* when `scale = TRUE`; skipped when
  `scale = FALSE`, since nothing rescales embeddings during alignment in
  that case, so there’s no drift to correct, and forcing a fixed size
  would destroy genuine average-size information a caller explicitly
  chose to keep. Locked down with a regression test asserting
  aligned-embedding magnitudes stay well above the collapsed-to-~0 range
  on real data.
- **Real production bug in
  [`run_embeddings_from_list()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/run_embeddings_from_list.md)/[`run_embeddings()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/run_embeddings.md):
  individual participant embeddings silently came back with exactly
  double the expected rows, half of them all-`NA`.** Found on a real
  36-item motion-triplets dataset (`part1_triplets.csv`, 55
  participants, purely-numeric `worker_id` values like `87059`) – each
  individual’s embedding had 72 rows instead of 36, while the *group*
  embedding (unaffected) was correctly 36 rows, which was the key clue
  that ruled out the vendored Python training code (shared by both
  paths) and pointed at the per-worker result-splitting step instead.
  Root cause, in `compute_embeddings.py::process_all_workers()`: each
  per-worker chunk tagged `emb_df['worker_id'] = worker_id` (the raw
  numpy int), while the pooled group chunk used the string `'group'`.
  `pd.concat()`-ing an int-typed column with a str-typed one forces
  pandas to an `object` dtype holding genuinely mixed int/str values;
  [`as.data.frame()`](https://rdrr.io/r/base/as.data.frame.html) can’t
  coerce that to one atomic R type on the way back to R, so it becomes
  an R **list column**. Comparing a list column with `==` (exactly what
  [`run_embeddings_from_list()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/run_embeddings_from_list.md)’s
  per-worker split does) then returns `NA`, not `FALSE`, for every row
  that doesn’t coerce to the comparison type – confirmed directly, with
  a minimal reproduction, that `list(87059L, 87059L, "group") == 87059`
  gives `TRUE TRUE NA`, not `TRUE TRUE FALSE` – and indexing a data
  frame with a logical selector containing `NA` inserts a bogus all-`NA`
  row for each one. Net effect: every individual’s embedding came back
  with one extra all-NA row per *other* chunk in the pool (every other
  participant, plus the group), which looked like exactly double
  whenever there was only one other worker plus the group. Only
  triggered when `worker_id` values are purely numeric-looking (pandas
  infers `int64` on `read_csv`) – string-like IDs such as `"p1"` (as in
  this package’s own `make_fake_triplet_list()` test fixture) were never
  affected, which is presumably why this went unnoticed; a regression
  test (`test-run_embeddings_from_list.R`) had to override the fixture’s
  worker IDs to numeric ones specifically to reproduce it, and was
  confirmed to actually fail against the pre-fix code before being
  locked in. Fixed by making every chunk’s `worker_id` a string
  (`str(worker_id)`) before concatenation, so the column’s dtype is
  consistent from the start.
- **[`read_raw_data()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/read_raw_data.md)
  now skips (with a warning) a CSV in `data_dir` that isn’t actually a
  raw trial-level export, instead of hard-erroring the whole directory
  read.** Found when the user pointed it at a real raw-export directory
  (`ColorTriplets/raw_data/part1`) that had accidentally picked up an
  unrelated precomputed-embeddings CSV
  (`embeddings_all_prolific_part1.csv` – `dim_0`/`item`/`worker_id`
  columns, no trial-category column at all, since it was never meant to
  be read as a trial export). Previously `read_one_raw_file()` called
  [`stop()`](https://rdrr.io/r/base/stop.html) the moment any file
  lacked a recognized trial-category column
  (`trial_category`/`sampleAlg`/`AlgSample`), aborting the entire
  [`read_raw_data()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/read_raw_data.md)
  call over one stray file. Now it
  [`warning()`](https://rdrr.io/r/base/warning.html)s (naming the file)
  and returns `NULL`;
  [`read_raw_data()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/read_raw_data.md)
  filters those out before `rbindlist()`-ing the rest, and only raises a
  hard error if *every* CSV in the directory gets skipped this way (a
  clearer message than the generic downstream failure that would
  otherwise result from an empty combined data frame). New tests
  (`test-read_raw_data.R`) cover all three cases: a stray file skipped
  with a warning while the valid file still reads correctly, an
  all-stray directory giving the new clear error, and a fully clean
  directory producing no warning at all.
- **Validation trials gained a third, clean “holdout” treatment,
  resolving a real double-dipping problem the user identified.**
  Validation trials repeat across participants (unlike `random` trials,
  which vary), making them the natural choice for a final
  cross-participant evaluation set – but only if nothing upstream of
  that evaluation ever touched them. Previously they could only be
  routed to `sampleSet = "train"` or `"test"`; if `"test"`, they’d still
  contaminate the early-stopping/model-selection criterion (which picks
  the best checkpoint by minimizing test loss), so evaluating on them
  afterward is double-dipping even though no gradient was ever computed
  on them directly. Fixed by adding a third option that sets
  `sampleSet = NA` for validation trials – the same treatment as check
  trials – which every model-fitting code path already excludes from
  both train and test matrices (confirmed directly across
  [`run_embeddings_from_list()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/run_embeddings_from_list.md),
  [`run_group_embedding_from_list()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/run_group_embedding_from_list.md),
  [`run_embeddings()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/run_embeddings.md),
  [`prepare_triplet_matrices()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/prepare_triplet_matrices.md),
  and
  [`reduce_embedding_dimension()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/reduce_embedding_dimension.md)
  before making this change, not assumed). Landed across four functions,
  all sharing the vocabulary `"train"`/`"test"`/`"holdout"`:
  - [`set_validation_behavior()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/set_validation_behavior.md)’s
    `mode` argument gained `"holdout"` – the natural place for this,
    since the function already existed specifically to switch
    validation-trial treatment on already-read data without redoing the
    train/test split.
  - [`assign_sample_sets()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/assign_sample_sets.md)’s
    `train_with_validation` (logical) was renamed to `validation_mode`
    (character: `"train"`/`"test"`/`"holdout"`, default `"train"`) – a
    deliberate breaking change (confirmed with the user rather than kept
    logical-compatible, since this is a small lab-internal package) for
    a cleaner, consistent 3-way vocabulary matching
    [`set_validation_behavior()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/set_validation_behavior.md).
    [`read_raw_data()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/read_raw_data.md)’s
    own `train_with_validation` parameter was renamed the same way and
    passed through.
  - [`get.hoacc()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/get.hoacc.md)’s
    `trialtype` argument now special-cases `"validation"`: since
    `sampleSet` never literally equals `"validation"` once holdout
    trials are excluded this way, it instead filters via
    `sampleAlg == "validation"` directly (erroring clearly if `td` has
    no `sampleAlg` column).
  - **Found and fixed a related bug while wiring this up**:
    [`get.prediction.matrix()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/get.prediction.matrix.md)
    (a thin per-pair wrapper around
    [`get.hoacc()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/get.hoacc.md))
    did its own redundant pre-filter by `sampleSet == ttype` *before*
    ever calling
    [`get.hoacc()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/get.hoacc.md),
    which would have silently selected nothing for
    `ttype = "validation"` even after fixing
    [`get.hoacc()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/get.hoacc.md)
    itself, since that pre-filter never had the sampleAlg-based special
    case. The pre-filter was fully redundant with what
    [`get.hoacc()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/get.hoacc.md)
    already does internally (its only use was being passed straight into
    [`get.hoacc()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/get.hoacc.md)),
    so it was simply removed –
    [`get.prediction.matrix()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/get.prediction.matrix.md)
    now passes each participant’s full, unfiltered triplet data frame
    through, letting
    [`get.hoacc()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/get.hoacc.md)’s
    own filtering (including the new validation handling) run on it
    directly.
  - [`get.participant.summary()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/get.participant.summary.md)’s
    `nvalidation` count was already computed from `sampleAlg`, not
    `sampleSet` – confirmed unaffected, no change needed.
  - New tests: `test-assign_sample_sets.R`,
    `test-set_validation_behavior.R`, plus new cases added to
    `test-get_hoacc.R` and `test-get_prediction_matrix.R` covering the
    validation-via-sampleAlg path specifically (including the
    [`get.prediction.matrix()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/get.prediction.matrix.md)
    regression, constructed so it would have failed against the pre-fix
    redundant-pre-filter code).
- **[`plot_3d_trajectory()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/plot_3d_trajectory.md)**
  (new) **+
  [`plot_2d_trajectory()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/plot_2d_trajectory.md)**
  (new) – both in `R/plot_3d_trajectory.R`, sharing a set of internal
  helpers.
  [`plot_3d_trajectory()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/plot_3d_trajectory.md)
  was ported in from a user-written analysis script (`ColorTriplets/R/`
  in the data directory) that built a 3-D scatterplot of one query point
  of a
  [`smooth_embedding_trajectory()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/smooth_embedding_trajectory.md)
  result, with a gray `effective_n` density strip along the bottom and a
  red marker at the point shown – exactly the kind of per-frame
  visualization needed to animate a trajectory (e.g. via `gifski`, as
  discussed earlier for the Gabor-wavelet dataset). `scatterplot3d`
  added to Suggests (new dependency; not previously used anywhere in the
  package). Two real design gaps surfaced and resolved with the user
  before integrating, not guessed at: (1) the original signature carried
  `n_query`/`bw` parameters that were never referenced anywhere in the
  function body – confirmed unused, then dropped; (2) `pos` (participant
  positions) was *also* unused in the original, but the user wanted it
  kept and wired up to plot each participant’s own position as a small
  black dot along the same bottom strip – implemented via a linear map
  from `range(traj$query_points)` onto the strip’s rendered x-extent,
  verified visually (not just “ran without erroring”): rendered a real
  plot on `icon_emb_ind` and confirmed the dots land exactly where
  separately-traced fraction values say they should (4 clustered near
  one edge, 2 near the other, matching this bundled dataset’s known
  small-vs-large participant split established earlier in this doc).
  Also answered a user question about the cleanest way to pass arbitrary
  `scatterplot3d` appearance parameters through: added `...`, merged
  with the function’s own defaults via
  [`modifyList()`](https://rdrr.io/r/utils/modifyList.html) then
  dispatched with [`do.call()`](https://rdrr.io/r/base/do.call.html) (so
  e.g. `angle =`/`grid =` can be overridden without the function needing
  a named parameter for every possibility) – plain `...` forwarding
  alone would have hit “formal argument matched by multiple actual
  arguments” errors on any of the names already hardcoded internally,
  which
  [`modifyList()`](https://rdrr.io/r/utils/modifyList.html)-before-[`do.call()`](https://rdrr.io/r/base/do.call.html)
  avoids.
  - `get_axis_ranges()` (computes shared, zero-centered axis limits
    across every query point so repeated calls at increasing `loc` don’t
    rescale frame to frame) needed a `na.rm = TRUE` fix while porting it
    in:
    [`smooth_embedding_trajectory()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/smooth_embedding_trajectory.md)
    can legitimately return an all-NA embedding for a query point with
    no meaningful kernel weight (its own documented behavior), and the
    original un-guarded
    [`min()`](https://rdrr.io/r/base/Extremes.html)/[`max()`](https://rdrr.io/r/base/Extremes.html)
    calls would have let one such point poison every axis’s range to
    `NA`.
  - `add_density_to_cube()` (kept close to the original) reaches into
    `scatterplot3d`’s own internal, non-exported closure variables to
    find where its 3-D cube actually renders in 2-D plot coordinates,
    since the package exposes no public API for this – documented
    clearly as a fragility inherent to the chosen graphics approach, not
    something with a clean fix available.
  - **Immediately after
    [`plot_3d_trajectory()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/plot_3d_trajectory.md)
    was done, the user asked for a 2-D sibling with the same argument
    conventions**
    ([`plot_2d_trajectory()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/plot_2d_trajectory.md),
    base
    [`graphics::plot()`](https://rdrr.io/r/graphics/plot.default.html),
    no new dependency). Rather than duplicating the
    bottom-strip/red-marker/participant-dot logic, refactored first:
    pulled the strip-drawing math out of `add_density_to_cube()` into a
    new `add_density_strip(xlim, density, ...)` that takes an explicit
    x-range instead of deriving one from a scatterplot3d object
    (`add_density_to_cube()` now just works out that xlim from the cube
    internals and delegates to it – a 2-D plot’s own x-range is already
    exactly `par("usr")[1:2]`, no cube-geometry reconstruction needed at
    all), and pulled the red-marker-plus-participant-dots logic out into
    `add_trajectory_markers(d, traj, pos, loc)`, used identically by
    both 2-D and 3-D versions. Also factored out the
    `loc`-bounds-checking into `validate_traj_loc()`, shared the same
    way.
    [`plot_2d_trajectory()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/plot_2d_trajectory.md)
    needed one thing the 3-D version didn’t: a `par(mar = ...)` bump for
    enough bottom-margin room for the strip to render via `xpd = TRUE`
    without being clipped at the figure boundary (`scatterplot3d()`
    handles its own margin internally via its own `mar` argument; base
    [`plot()`](https://rdrr.io/r/graphics/plot.default.html) has no
    equivalent, so this function sets it directly) – saved and restored
    via [`on.exit()`](https://rdrr.io/r/base/on.exit.html) so it doesn’t
    leak into the caller’s later plots (confirmed with a dedicated test
    comparing `par("mar")` before and after). Both new plots verified
    visually, not just “ran without erroring”: rendered real PNGs on
    `icon_emb_ind` and confirmed the strip, red marker, and black
    participant dots all land in the expected positions in both the 2-D
    and 3-D cases.
  - All five helpers (`get_axis_ranges()`, `validate_traj_loc()`,
    `add_density_strip()`, `add_density_to_cube()`,
    `add_trajectory_markers()`) kept internal (not exported), matching
    this package’s existing convention for small single-purpose
    supporting functions (e.g. `read_raw_data.R`’s own internal helpers)
    – only
    [`plot_3d_trajectory()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/plot_3d_trajectory.md)/[`plot_2d_trajectory()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/plot_2d_trajectory.md)
    themselves are exported.
- **Real bug found and fixed in `add_trajectory_markers()` right after
  the functions above shipped: participant-position dots were
  essentially invisible.** The user reported “it all works without
  error, but I’m not seeing black dots” even after rendering large.
  Chased two hypotheses before finding the real one, each tested
  directly rather than assumed: (1) suspected `pos` being passed as a
  raw `cmdscale(d, k=1)` **matrix** (confirmed from the user’s real
  notebook, `ColorTriplets/Color_analysis.Rmd`:
  `pos <- cmdscale(p1rd, 1)`, no `[,1]` extraction –
  [`cmdscale()`](https://rdrr.io/r/stats/cmdscale.html) always returns a
  matrix, even for `k=1`, a well-known general R gotcha) – reproduced
  this exact pattern directly, but traced the actual arithmetic step by
  step (via
  [`assignInNamespace()`](https://rdrr.io/r/utils/getFromNamespace.html)-instrumented
  debug prints on the real call path, not just an isolated
  reconstruction) and found the position math was computing correctly
  regardless, and separately confirmed
  [`smooth_embedding_trajectory()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/smooth_embedding_trajectory.md)
  itself is also unaffected by a matrix `positions` argument
  ([`identical()`](https://rdrr.io/r/base/identical.html)-checked every
  field of a `traj` built with the matrix against one built with the
  equivalent vector); (2) the user then asked directly whether the gray
  density bars might be painted *after* the dots, hiding them (z-order)
  – tested this conclusively by manually overdrawing huge, bright
  magenta markers at the exact same computed coordinates on top of a
  real rendered plot and confirming they appeared clearly on top, ruling
  out z-order/clipping entirely. The actual cause: the dots were real,
  correctly positioned, and correctly drawn on top the whole time – just
  `pch = 20, cex = 0.5`, which is too small and low-contrast to reliably
  spot against the gray density-strip’s own tick-mark-like bars at
  realistic plot sizes (confirmed by rendering the same real data larger
  – still essentially unnoticeable). Fixed by bumping the default to
  `pch = 19, cex = 1.1`, now clearly visible at normal sizes in both the
  2-D and 3-D versions (shared via `add_trajectory_markers()`). Also
  kept the matrix-`pos` defensive fix from hypothesis (1) even though it
  turned out not to be the actual root cause here:
  `drop(as.matrix(pos))` now silently handles a 1-row or 1-column matrix
  (the exact [`cmdscale()`](https://rdrr.io/r/stats/cmdscale.html)
  mistake) and raises a clear error for a genuine multi-column matrix
  instead of silently misreading it – a real, confirmed-easy-to-hit
  foot-gun worth guarding against regardless of whether it was the cause
  of this particular report. Two new regression tests lock down the
  matrix-handling behavior specifically.
  - **Even after that fix shipped and was reinstalled, the user still
    reported no dots in their real notebook** – every package-level
    check passed (`body(tripletTools:::add_trajectory_markers)` showed
    the fix; `par("usr")`/manual position math were all correct;
    `xaxt`/`tick.marks` suppression, tested directly, made no
    difference), yet a [`trace()`](https://rdrr.io/r/base/trace.html)
    placed on `add_trajectory_markers()` fired only when called
    manually, never when invoked through a normal top-level
    `plot_3d_trajectory(...)` call – the decisive clue that the
    package’s own exported function was never actually being reached.
    Root cause: not a package bug at all – RStudio’s default “restore
    .RData on startup” had reloaded an old global-environment copy of
    `plot_3d_trajectory` (originally
    [`source()`](https://rdrr.io/r/base/source.html)-d from the user’s
    pre-package standalone script), which R resolves before the package
    namespace on every bare call, silently shadowing the reinstalled,
    fixed version with no error or warning of any kind. Resolved by
    clearing the workspace and re-running cleanly; confirmed fixed by
    calling the fully-qualified
    [`tripletTools::plot_3d_trajectory()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/plot_3d_trajectory.md)
    directly. General lesson worth remembering for any future “works in
    my test, not in the user’s session” mismatch: check
    `environment(fn)` for unexpected global-env shadowing *before*
    assuming the installed package code itself is at fault, especially
    on a second report after a fix that already checked out correctly in
    isolation.
- **`vignettes/trajectory_vignette.Rmd`** – new vignette built on top of
  [`plot_3d_trajectory()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/plot_3d_trajectory.md)/[`plot_2d_trajectory()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/plot_2d_trajectory.md)/[`smooth_embedding_trajectory()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/smooth_embedding_trajectory.md)/[`generalized_procrustes()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/generalized_procrustes.md)
  once the dot bug above was fully resolved, directly adapted from the
  user’s own real analysis notebook (`ColorTriplets/Color_analysis.Rmd`)
  rather than written from scratch. Demonstrates treating individual
  differences as a *continuous* manifold (as an alternative to the
  discrete-clustering tools covered in
  [`vignette("tripletTools")`](https://knowledge-and-concepts-lab.github.io/tripletTools/articles/tripletTools.md)),
  using a real dataset chosen specifically because it shows this cleanly
  in a domain where that kind of heterogeneity might not be expected: 58
  color patches, 46 participants, from Zimnicki et al.’s CogSci poster
  work (unpublished otherwise –
  <https://escholarship.org/uc/item/8778p3t3>, cited directly in the new
  data objects’ `@source`). New bundled datasets, same `icon_*`
  convention (`inst/extdata/color_*.csv` -\>
  `data-raw/color_triplets.R`/`data-raw/color_embeddings.R` -\>
  `data/*.rda`, see “Data objects” above): `color_triplets` (340KB
  compressed, the largest triplet dataset bundled so far – 46
  participants vs. `icon_triplets`’ 6 – checked compression first rather
  than assuming it’d be fine, since the raw CSV is ~30x
  `icon_all_triplets.csv`‘s size), `color_emb_ind`, `color_emb_group`,
  and a genuinely new kind of object for this package, `color_lab` (the
  patches’ own CIE LAB coordinates – not a fitted embedding, a reference
  point for comparison). **Caught a real, easy-to-miss correctness bug
  while building this, before it reached the vignette**: confirmed
  directly (not assumed) that `color_lab` and
  `color_emb_group`/`color_emb_ind` are *not* stored in the same row
  order, which would have silently misaligned items in any
  row-positional comparison
  (e.g. [`vegan::procrustes()`](https://vegandevs.github.io/vegan/reference/procrustes.html),
  which matches configurations by row position, not rowname) – the
  vignette always re-indexes by rowname first
  (`color_lab[rownames(color_emb_group), ]`), and this is called out
  explicitly in `color_lab`’s own roxygen docs as a standing gotcha for
  this specific pair of objects. Every number and figure in the vignette
  was independently computed and visually inspected (rendered PNGs read
  directly) before being written into the prose, not assumed from the
  analogous real notebook – this surfaced one genuine, interesting
  result worth noting for its own sake:
  [`estimate_intrinsic_dimension()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/estimate_intrinsic_dimension.md)
  on the participant representational-distance matrix comes back
  `forced_to_one = TRUE`, which is exactly the documented false-negative
  pattern from that function’s own history (dominance ratio ~4.9x)
  rather than a genuine absence of structure, and the vignette uses this
  as a live, real-data example of that exact documented caveat rather
  than inventing a synthetic one. The final payoff figure (held-out
  validation accuracy from the two ends of the smoothed manifold,
  plotted against each participant’s own manifold position) shows a
  clean, strong crossover (R² = 0.70 from a 16-query-point grid) –
  confirmed visually before writing it up, not just from the regression
  number alone. Vignette verified end-to-end via
  [`rmarkdown::render()`](https://pkgs.rstudio.com/rmarkdown/reference/render.html)
  (all 27 chunks, no errors/warnings) with output read back and
  spot-checked against the independently-computed values. Added to the
  vignette list in `README.md` and the `Repository layout` section
  above.
  - **Real bug the user caught after reading the rendered vignette, not
    caught by my own verification pass**: the two “True LAB” panels
    under “Does the group embedding recover real color space?” had
    visibly shuffled colors relative to the identical-data panels one
    section above. Root cause: `pcols` had been derived once from
    `color_lab`’s own row order (correct for the first section, which
    plots `color_lab` directly), then reused in the next chunk against
    `lab_matched`/`aligned`, which are in `color_emb_group`’s different
    row order – the alignment math itself was correctly row-matched
    (verified separately beforehand), but the `bg =` plotting color for
    each point was not. Checking afterward turned up the same risk a
    second place:
    `plot_3d_trajectory(traj, pos, loc = i, pcols = pcols, ...)` in the
    trajectory-grid section also needs `pcols` in embedding order
    (`traj$embeddings[[i]]` preserves
    `color_emb_ind`/`color_emb_group`’s row order, confirmed directly),
    which it happened to already be, but only by accident of chunk
    ordering, not by design. Fixed properly rather than patched
    per-chunk: confirmed all embedding-side objects (`color_emb_group`,
    every `color_emb_ind[[i]]`) already share one identical row order,
    so the vignette now establishes `pcols <- rownames(color_emb_group)`
    exactly once near the top and re-indexes `color_lab` to match it at
    that same point (`lab_matched <- color_lab[pcols, ]`), with every
    later chunk reusing those same two objects rather than re-deriving
    row order locally. Re-rendered and re-verified by extracting the
    embedded PNGs straight out of the rendered HTML (`base64`-decoded)
    and visually confirming the previously-mismatched panels now exactly
    match, and that the trajectory-grid colors cohere into a smooth
    gradient around the final ring frame. Worth remembering generally:
    verifying that an alignment/statistical *computation* used correctly
    row-matched inputs is not the same check as verifying every *plot*
    built from its output used a color/label vector in that same row
    order – these are separate things to check, and only the rendered
    figure actually catches the latter.
- **[`run_embeddings_from_list()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/run_embeddings_from_list.md)/[`run_embeddings()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/run_embeddings.md)
  gained a `compute_group` argument (default `TRUE`, preserving prior
  behavior)** letting a caller skip the group-level embedding entirely
  when only the per-participant ones are needed. Threaded through all
  three layers of the pipeline:
  `inst/python/compute_embeddings.py::process_all_workers()` gained the
  actual `compute_group` parameter and now wraps its whole “Group-level
  embedding across all workers” block (including the
  `embeddings_group.csv` write and the `"group"`
  `model_history`/`embeddings` row) in `if compute_group:` rather than
  running it unconditionally;
  [`run_embeddings()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/run_embeddings.md) (R)
  passes the flag straight through to that Python call;
  [`run_embeddings_from_list()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/run_embeddings_from_list.md) (R)
  passes it through again and, when `FALSE`, sets `group = NULL`
  directly rather than trying to extract a `"group"` row that was never
  written (which would otherwise silently produce a zero-row matrix
  instead of a clear `NULL`). Verified live, not just by reading the
  code: ran the real Python backend (available in this dev environment)
  with `compute_group = FALSE` and confirmed from the actual training
  log that “Processing group-level embedding across all workers…” never
  printed for that run, while it did for an otherwise-identical default
  (`compute_group = TRUE`) run just before and after it in the same test
  session. New regression test (`test-run_embeddings_from_list.R`)
  checks `res$group` is `NULL`, no `"group"` row in `res$history`, and
  `embeddings_group.csv` isn’t written to `output_dir`.
- **Real, pre-existing bug found and fixed: `seed` never actually
  controlled individual/group embedding fits in
  [`run_embeddings_from_list()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/run_embeddings_from_list.md)/[`run_embeddings()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/run_embeddings.md)/[`run_group_embedding_from_list()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/run_group_embedding_from_list.md).**
  Surfaced when the user reported that a real dataset fit with
  `compute_group = FALSE` came out “much worse” than a prior run, and
  asked for the recently-revised code to be double-checked before
  spending a long re-fit to isolate the cause. Diff inspection first
  ruled out `compute_group` itself: the per-worker fitting loop in
  `process_all_workers()` is byte-for-byte unchanged by that commit, and
  the (now-optional) group fit always runs strictly *after* the entire
  per-worker loop finishes, so it cannot feed back into individual fits
  either way. Confirmed this empirically too, not just by reading the
  diff – a quick synthetic-data check showed `compute_group = TRUE` vs
  `FALSE` gave *different* individual embeddings even with the same
  `seed`, which led to the real root cause: a control test with
  **identical** arguments (same `compute_group`, same `seed`) on two
  separate calls *also* gave different embeddings. Traced directly:
  `train_embedding_model()` only seeds `numpy`/`torch` when its own
  `random_state` argument is non-`None`
  (`if random_state is not None: np.random.seed(...); torch.manual_seed(...)`),
  but `process_all_workers()`’s per-worker loop and group-fitting block
  never passed `random_state` at all – always `None`. Meanwhile
  [`run_embeddings()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/run_embeddings.md)’s
  R-level `seed` argument only called `random$seed(as.integer(seed))`,
  seeding **Python’s built-in `random` module**, which
  `train_embedding_model()` never reads (confirmed `random` is imported
  in `compute_embeddings.py` but never actually called anywhere in the
  file). So `seed` was a complete no-op for fit reproducibility the
  whole time – two calls with identical arguments could, and did,
  produce meaningfully different embeddings purely from uncontrolled
  weight initialization, independent of any data or code change. The
  exact same gap existed in the sibling function
  [`run_group_embedding_from_list()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/run_group_embedding_from_list.md):
  it called `set.seed(seed)` (R-level only) but never passed
  `random_state` to its own
  [`train_embedding()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/train_embedding.md)
  call either, even though
  [`train_embedding()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/train_embedding.md)
  already supports `random_state` correctly (confirmed by checking that
  function’s own tests, which explicitly reproduce embeddings via it) –
  fixed by following that exact already-working pattern, rather than
  inventing a new one.
  - Fix, threaded through properly rather than patched at one layer:
    `process_all_workers()` (Python) gained a `seed=None` parameter;
    each worker now gets `random_state = seed + worker_index` (0-based
    position among `df['worker_id'].unique()`, stable since the input
    CSV’s row order comes directly from `triplet_list`’s own R list
    order) and the group fit (if computed) gets
    `seed + len(unique_worker_ids)` – one past the last worker index,
    guaranteed collision-free.
    [`run_embeddings()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/run_embeddings.md) (R)
    now passes `seed = as.integer(seed)` through to
    `process_all_workers()` and no longer calls the dead
    `random$seed()`/`reticulate::import("random")` lines at all.
    [`run_group_embedding_from_list()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/run_group_embedding_from_list.md)
    now passes `random_state = as.integer(seed)` to its
    [`train_embedding()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/train_embedding.md)
    call (its pre-existing `set.seed(seed)` is left in place, since that
    still legitimately controls the R-level
    [`sample()`](https://rdrr.io/r/base/sample.html) shuffle used in its
    70/30 train/test fallback path).
  - Verified live, not just by reading the fix: re-ran the exact control
    test that exposed the bug (identical arguments, two separate calls)
    and confirmed [`identical()`](https://rdrr.io/r/base/identical.html)
    now holds for every participant’s embedding *and* the group
    embedding; confirmed a *different* seed still gives a different
    embedding (not a degenerate always-the-same-output bug); re-ran the
    `compute_group = TRUE` vs `FALSE` comparison with the fix in place
    and confirmed individual embeddings are now
    [`identical()`](https://rdrr.io/r/base/identical.html) regardless of
    the flag, closing the loop on the user’s original report. The
    duplicate-training-curve evidence is visible directly in the
    test-run log (`[early stop]` loss/accuracy trajectories repeating
    verbatim across two “same seed” calls). New regression tests in
    `test-run_embeddings_from_list.R` and
    `test-run_group_embedding_from_list.R` lock all of this down; the
    latter’s existing `norm_penalty` test had its own comment
    documenting the then-known “runs aren’t reproducible enough to
    compare” limitation, now stale and removed.
  - Open question the user’s original report leaves unresolved: whether
    their perceived “much worse” embeddings were *entirely* explained by
    this pre-existing non-determinism, or whether their own acknowledged
    test/validation-trial treatment changes also contributed. With
    `seed` now actually working, re-running their real dataset with a
    fixed `seed` (with and without their data changes) would cleanly
    separate the two – not yet done, since it requires their real,
    slow-to-fit dataset.
- **[`plot_pics()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/plot_pics.md)
  fixed to preserve each image’s own native pixel aspect ratio, instead
  of stretching it to match the plotting surface’s.** Root cause: the
  old sizing code computed `xsz <- psize * xrange` and
  `ysz <- psize * yrange` independently from the axis data ranges alone
  – working out the actual *physical* box size this produces (via
  `par('pin')`, the plot region’s size in inches) shows the rendered
  box’s physical width/height ratio always equals `pin[1]/pin[2]` (the
  plotting region’s own aspect ratio), regardless of the image’s own
  shape – so any non-square plotting window (the common case –
  e.g. `png(width=, height=)` with unequal width/height) silently
  stretched every image to match the window, not just unusual cases.
  Fixed by anchoring `psize` to physical height only (`psize * pin[2]`,
  unchanged in spirit from before) and deriving the box’s width from the
  image’s own native aspect ratio (`dim(currpic)[2]/dim(currpic)[1]`,
  works for both PNG arrays and `"raster"` matrices) combined with the
  actual data-units-per-inch conversion in each direction – factored
  into a new internal (non-exported) helper,
  `compute_pic_halfsize(native_ar, psize, pin, xlim, ylim)`,
  deliberately taking `pin`/`xlim`/`ylim` as plain arguments rather than
  reading [`par()`](https://rdrr.io/r/graphics/par.html) itself so it’s
  unit-testable without a live graphics device. Verified algebraically
  (worked through by hand before implementing, confirming the new
  formula reduces to the exact old one when both the image and the
  plotting device are square) and empirically:
  `tests/testthat/test-plot_pics.R` checks the physical aspect ratio
  comes out correct for a square image on a non-square device and for a
  non-square (2:1) image on a non-square device with non-square axis
  ranges, plus a real rendered check on `icon_pics` at an extreme
  1400x500 (2.8:1) device confirming the icons render square and
  undistorted, where they’d have been visibly squished under the old
  code.
- **[`assign_sample_sets()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/assign_sample_sets.md)
  changed from an independent per-trial coin-flip to an exact
  per-participant count**, at the user’s request. Previously
  `sampleAlg == "random"` trials were each independently assigned to
  test via `runif(n()) <= test_prop`, so the *number* of test trials per
  participant only matched `test_prop` in expectation – two participants
  with the same number of random trials could (and typically did) end up
  with different test-set sizes. Now a new internal (non-exported)
  helper, `select_test_trials()`, computes
  `n_test = round(test_prop * n_random)` once per participant and
  selects exactly that many random trials (via
  `sample.int(n_random, n_test)`, without replacement) to be test – so
  same trial count always means same test count, and different trial
  counts still get matched *proportions* with a controlled,
  deterministic-given-seed exact count. Kept the existing
  `case_when()`/`group_by(worker_id)` structure, just swapped the
  `random`-trial branch’s condition for a call to the new helper
  (computed in a [`{ }`](https://rdrr.io/r/base/Paren.html) block inside
  the single `mutate()` call, so the intermediate logical vector doesn’t
  leak out as a stray column). Verified the existing claim in this
  function’s own docs still holds after the change – validation trials
  still never consume any of `test_prop`’s random draws, since
  `select_test_trials()` only looks at `sampleAlg == "random"` rows and
  runs identically regardless of `validation_mode` – and added new
  regression tests locking down the exact-count property directly (same
  `n_random` -\> same test count across participants;
  [`round()`](https://rdrr.io/r/base/Round.html)’s exact behavior at a
  non-round `test_prop * n_random`; the `test_prop ∈ {0, 1}` extremes; a
  zero-random-trials participant not erroring).
- **[`loo_trajectory_accuracy()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/loo_trajectory_accuracy.md)**
  (new) – fixes a second, independently real data-leakage bug in the
  [`smooth_embedding_trajectory()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/smooth_embedding_trajectory.md)
  prediction workflow, found by the user noticing an apparent
  contradiction:
  [`test_dominant_dimension()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/test_dominant_dimension.md)
  gave a non-significant p (~0.1) on a real dataset where PC1 explained
  only ~9% of variance (dominance_ratio ~2, matched almost exactly to
  this function’s own validated “weak, correctly-not-detected” synthetic
  case), yet the user’s own crossover-prediction analysis
  (left-end/right-end smoothed embeddings predicting held-out judgments)
  showed a strong, clean crossover – which the user read as evidence
  [`test_dominant_dimension()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/test_dominant_dimension.md)
  was underpowered/wrong.
  - **Root cause, confirmed empirically rather than argued
    theoretically**:
    [`smooth_embedding_trajectory()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/smooth_embedding_trajectory.md)’s
    kernel weighting gives “no participant’s weight ever exactly zero”
    (its own pre-existing docs) – so a participant near the left end of
    the manifold contributes, with real weight, to the very left-end
    smoothed embedding later evaluated against *their own* held-out
    judgments. A participant’s own fitted embedding unsurprisingly
    predicts their own behavior better than a random other participant’s
    would, regardless of whether any genuine cross-participant structure
    exists at all – so the crossover test as commonly used (compute the
    trajectory once on everyone, then evaluate each participant against
    their nearest query point) cannot distinguish “real shared structure
    with actual neighbors” from “trivial self-contribution.”
    Demonstrated directly: a synthetic dataset of participants with
    fully independent, unrelated true embeddings (zero real structure,
    by construction) produced a strong, “significant”-looking crossover
    (R-squared 0.27, p = 0.003) under the naive approach – collapsing to
    non-significance (R-squared 0.06, p = 0.18) once each participant
    was excluded from just the smoothing step, and to near-zero
    (R-squared 0.004, p = 0.80) once fully excluded, including from the
    1-D axis computation itself (the stricter version this function
    implements).
  - **What it does**: for every participant, drops them entirely (from
    `dist_mat` before `cmdscale` computes the 1-D axis, and from `elist`
    before
    [`smooth_embedding_trajectory()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/smooth_embedding_trajectory.md)
    refits the trajectory on the remaining n-1), then evaluates their
    held-out trials (`trialtype`, typically `"validation"`) against
    every one of `n_query` query points along that fully out-of-sample
    trajectory – giving an `n` x `n_query` accuracy matrix per
    participant, rather than one number per participant at whichever
    single query point happened to be nearest them. Returns
    `query_points` and `effective_n` per participant too (these shift
    slightly participant to participant, since each leave-one-out fit
    spans a slightly different (n-1)-participant range), plus
    `full_sample_position` (each participant’s position from the *full*,
    non-leave-one-out sample) for context/plotting only – never used in
    any prediction.
  - [`get.rep.dist()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/get.rep.dist.md)’s
    pairwise distances were confirmed (read directly, not assumed) to
    depend only on the two participants in each cell – so subsetting the
    already-computed `dist_mat` per left-out participant is exactly
    equivalent to recomputing
    [`get.rep.dist()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/get.rep.dist.md)
    from scratch on the remaining participants, no expensive distance
    recomputation needed.
  - [`smooth_embedding_trajectory()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/smooth_embedding_trajectory.md)’s
    own roxygen gained a new warning section () pointing to this
    function, so the pitfall is documented where someone would naturally
    first encounter the tool that has it, not only here.
  - **Resolved** (numbers below superseded two bullets down, once the
    bundled `color_emb_ind` data itself turned out to be stale):
    `vignettes/trajectory_vignette.Rmd` re-verified with
    [`loo_trajectory_accuracy()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/loo_trajectory_accuracy.md)
    and fixed. The crossover section now explicitly explains the leakage
    pitfall in prose (not just a passing mention) before showing the
    corrected analysis, since this is exactly the kind of mistake a
    reader could otherwise repeat.
- **[`test_dominant_dimension()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/test_dominant_dimension.md)**
  (new) + integration into
  [`estimate_intrinsic_dimension()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/estimate_intrinsic_dimension.md)
  (new `dominance_p_value`, `test_dominance`/`n_simulations` args) – a
  direct, simulation-based statistical test for exactly the weakness
  [`estimate_intrinsic_dimension()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/estimate_intrinsic_dimension.md)’s
  own docs already flagged (Horn’s PA conservatism at rank 1, previously
  only hinted at via the `dominance_ratio` heuristic). Motivated by the
  user noticing the same pattern across several real datasets:
  `forced_to_one = TRUE` with a clearly dominant leading eigenvalue (4x+
  the rest), wanting something more statistically justified than a ratio
  heuristic.
  - **Two earlier designs were tried and both failed real validation,
    not shipped**: (1) bootstrap-eigenvector-stability (Jackson 1993;
    Peres-Neto, Jackson & Somers 2003/2005 – genuine precedent, verified
    via search, for testing PCA axis stability under bootstrap
    resampling) – failed because
    [`estimate_intrinsic_dimension()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/estimate_intrinsic_dimension.md)’s
    `coords` come from
    [`cmdscale()`](https://rdrr.io/r/stats/cmdscale.html), which is
    *already* orthogonal by construction, so re-eigendecomposing
    bootstrap-resampled copies of it just rediscovers whichever column
    has the most variance regardless of whether that dominance is real
    or sampling noise; three variants (direct, correlation-standardized,
    full cmdscale-refit-per-bootstrap-draw) were tried and all three
    gave statistically indistinguishable “stability” for genuine
    synthetic structure vs. pure noise in controlled tests. (2) The
    literal asymptotic Tracy-Widom distribution (Johnstone 2001;
    Patterson, Price & Reich 2006) – ruled out before implementing, via
    a literature check confirming its accuracy is well documented to
    degrade “when either the sample size or dimension is not too large”
    – exactly this package’s regime (participant counts in the tens, not
    thousands).
  - **What actually worked, found by going back to Horn’s own original
    1965 parallel-analysis proposal** (simulated random data) rather
    than the permutation variant of Buja & Eyuboglu (1992) that
    [`estimate_intrinsic_dimension()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/estimate_intrinsic_dimension.md)
    already implements – but with two modifications that were
    *necessary*, confirmed by testing, not assumed: simulating the null
    at **equal** variance across candidate dimensions (not matched to
    the observed data’s own per-dimension variances, which is what both
    Horn’s original method and permutation do, and is exactly what
    reintroduces the “beat a shuffled/simulated version of itself”
    problem for a dominant first axis), and testing the
    **scale-invariant proportion of variance explained** by the
    dimension in question rather than raw eigenvalue magnitude (needed
    since the observed data and a unit-variance null simulation aren’t
    otherwise on comparable scales). This is a specific combination this
    package arrived at via testing, not a direct implementation of any
    one cited paper’s exact method – documented as such in the
    function’s own roxygen rather than overclaiming precedent.
  - **Validated directly before shipping** (own `@section Validation`,
    and locked into the test suite): Type I error close to nominal at n
    = 6, 20, and 30 (observed false-positive rates 4.7-8.7% at alpha =
    0.05/0.10); correctly non-significant for pure noise and a weak
    (variance ratio 2) synthetic dominant dimension; correctly
    significant from ratio \>= 5 at both n = 6 and n = 30. On the real
    `icon_emb_ind` data (n = 6, `dominance_ratio` 5.64), gives p = 0.38
    – an honest “can’t distinguish from noise at this sample size”
    rather than a false positive, illustrating that a large
    `dominance_ratio` alone is not sufficient evidence at very small n.
  - [`estimate_intrinsic_dimension()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/estimate_intrinsic_dimension.md)
    calls
    [`test_dominant_dimension()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/test_dominant_dimension.md)
    directly (rank 1) rather than inlining/sharing loop state with its
    own permutation test, since the new test’s simulation is entirely
    independent of Horn’s permutation null – simpler and no real
    efficiency cost. `test_dominance = TRUE` is the new default
    (backward-compatible return shape: existing callers just get one new
    always-present `dominance_p_value` field, `NA` when
    `test_dominance = FALSE`).
- **Real data-quality bug in the bundled `color_emb_ind` dataset: it was
  fit with validation trials leaking into training, making every
  [`test_dominant_dimension()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/test_dominant_dimension.md)/[`loo_trajectory_accuracy()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/loo_trajectory_accuracy.md)
  number already shipped in `trajectory_vignette.Rmd` wrong.** Surfaced
  when the user ran `test_dominant_dimension(p1rd)` in their own,
  independently-refit notebook (`ColorTriplets/Color_analysis.Rmd`) and
  got p ≈ 0.09, sharply different from the vignette’s reported p =
  0.001. The user’s own diagnosis: “I think in the older version the
  validation trials had been included when fitting embeddings… I
  recomputed everything after setting validation trials to ‘holdout’.”
  Confirmed precisely rather than taken on faith, three ways: (1)
  `table(sampleAlg, sampleSet)` on the bundled `color_triplets.csv`
  showed all 3864 validation trials at `sampleSet = "train"` –
  consistent with, though not proof of, leakage at fit time (triplets
  CSVs always show this regardless of holdout status, since
  [`set_validation_behavior()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/set_validation_behavior.md)’s
  `"holdout"` setting is applied in-memory and never written back to
  disk – the real question is always what `sampleSet` was *at fit time*,
  not what the raw CSV shows); (2) direct `md5sum` comparison of the
  bundled `inst/extdata/color_embeddings_individual.csv` against the
  user’s current live refit showed genuinely different hashes and
  different coordinate values for the same worker/item cells; (3) the
  decisive check – the user’s `fitdata_p1_3d.csv` (per-fit training/test
  triplet counts) showed `n_train_triplets = 29459` for every individual
  fit, which is exactly the random-trials-only count with the 3864
  validation trials excluded (not 29459+3864 = 33323, which is what
  leakage would produce) – confirming the user’s *current* files are the
  methodologically correct, holdout-respecting fits.
  - **Scope was narrower than it first looked.** `md5sum` comparison of
    all three raw inputs showed the bundled **group embedding**
    (`color_embeddings_group.csv`) and the bundled **raw triplets**
    (`color_triplets.csv`) are byte-identical to the user’s current live
    files – only the **individual embeddings**
    (`color_embeddings_individual.csv`) were stale. (The group
    embedding’s `n_train_triplets = 29459` in the same
    `fitdata_p1_3d.csv` independently confirms it too was already fit
    correctly, despite its file timestamp looking slightly older than
    the individual-embeddings refit – timestamps on their own would have
    been misleading here; the fit-stats count is what actually settles
    it.) So only `color_emb_ind`/`data/color_emb_ind.rda` needed
    re-bundling, not `color_emb_group` or `color_triplets`.
  - Fixed by copying the user’s current
    `ColorTriplets/embeddings/p1_3d_ind.csv` over
    `inst/extdata/color_embeddings_individual.csv` and re-running
    `data-raw/color_embeddings.R`’s individual-embedding block to
    regenerate `data/color_emb_ind.rda`. No R/ code changed – this was
    purely a stale-data problem, confirmed by the full test suite (540
    tests) passing unchanged before and after (no test depends on
    `color_emb_ind`’s specific values).
  - `vignettes/trajectory_vignette.Rmd` recomputed end-to-end against
    the corrected data and rewritten to match, not just patched with new
    numbers:
    [`test_for_clusters()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/test_for_clusters.md)’s
    Hopkins statistic is now *significant* (p = 0.021, was
    non-significant before) while BIC still prefers `best_g = 1` –
    re-framed in prose as exactly the signature a continuous
    (non-discrete) axis should leave on Hopkins, rather than
    contradicting the “no discrete subgroups” conclusion.
    [`test_dominant_dimension()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/test_dominant_dimension.md)
    now gives p = 0.096 (not 0.001) on this dataset – i.e. the color
    dataset is now itself the “dominance test doesn’t reach
    significance” case, matching what the user’s own notebook found.
    [`loo_trajectory_accuracy()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/loo_trajectory_accuracy.md)’s
    crossover R² is 0.638 (not 0.676) but remains highly significant (p
    = 2.9e-12) and visually clean (re-rendered and inspected directly,
    not assumed). This produced a better, more honest narrative arc than
    the stale version had: the vignette now explicitly uses its own
    [`test_dominant_dimension()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/test_dominant_dimension.md)
    non-result as the motivating tension the leave-one-out behavioral
    analysis resolves (“a p-value of 0.096 on the geometry alone is not
    a confident detection… the decisive evidence comes from asking that
    geometry to actually predict something”), rather than reporting two
    independently-significant results that happened to agree. Verified
    via full
    [`rmarkdown::render()`](https://pkgs.rstudio.com/rmarkdown/reference/render.html)
    (27 chunks, no errors) with the rendered crossover figure visually
    inspected.
  - General lesson distinct from the icon_emb_group rownames fix earlier
    in this file: that was a *format* bug caught by code inspection;
    this was a *fit-correctness* bug that could only be caught by
    comparing shipped data against an independently-refit version and
    checking per-fit training counts – a reminder that bundled
    “precomputed” data objects can silently drift out of sync with the
    pipeline code/conventions that produced them, with no test or lint
    able to catch it automatically.
- **[`plot_2d_trajectory()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/plot_2d_trajectory.md)
  gained an explicit `mar` parameter, fixing a real “can’t control plot
  margins” report.** The user found the function left a lot of
  whitespace around each panel and was “immune” to `par(mar = ...)`,
  whether set externally beforehand or passed through `...`. Root cause:
  unlike
  [`plot_3d_trajectory()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/plot_3d_trajectory.md)
  (where `mar` is just one more
  [`scatterplot3d::scatterplot3d()`](https://rdrr.io/pkg/scatterplot3d/man/scatterplot3d.html)
  argument, already reachable through the existing `...`/`modifyList`
  mechanism),
  [`plot_2d_trajectory()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/plot_2d_trajectory.md)
  set its margin via a hardcoded internal
  `graphics::par(mar = c(6, 4, 2, 2))` call, entirely outside that
  mechanism – `...` only ever reached
  [`graphics::plot()`](https://rdrr.io/r/graphics/plot.default.html)
  (which has no `mar` argument of its own to receive it), and any
  external `par(mar = ...)` the caller had already set was captured and
  overwritten by that same hardcoded call for the duration of the
  function (then correctly restored afterward via the existing
  [`on.exit()`](https://rdrr.io/r/base/on.exit.html) – so it wasn’t a
  restore bug, the margin was just never settable in the first place).
  Fixed by promoting the hardcoded value to an explicit
  `mar = c(6, 4, 2, 2)` parameter (same default, so existing callers are
  unaffected) used directly in that
  [`par()`](https://rdrr.io/r/graphics/par.html) call. Verified
  visually, not just by reading the fix: rendered a real 4x4 grid of
  panels with the default `mar` (showing the reported excess whitespace)
  against the same grid with `mar = c(2.5, 1, 1, 1)` (packing tightly,
  with the `effective_n` density strip and red marker still rendering
  correctly, not clipped).
- **[`find_frequent_triplets()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/find_frequent_triplets.md)**
  (new) – for retrofitting a post-hoc validation set onto legacy data
  collected before the `sampleAlg == "validation"` convention existed,
  where every triplet was instead sampled independently at random per
  participant. The user’s stated question going in was whether this is
  even feasible, given how fast the number of distinct triplets grows
  with item count – for a study with only 10 items
  (`10 * choose(9, 2) = 360` distinct `Center`/`{Left, Right}`
  combinations), real cross-participant overlap is plausible even from
  independent random sampling, unlike larger item sets. Counts, per
  distinct triplet (identity via
  [`make.tripnames()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/make.tripnames.md),
  the same left/right-independent convention
  [`make.vmat()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/make.vmat.md)
  uses for genuine validation trials – same `Center` + same unordered
  `{Left, Right}` pair, but a different `Center` on the same three items
  is a different question, counted separately), both `n_participants`
  (distinct `worker_id`s who judged it – the primary ranking key) and
  `n_trials` (total judgments, which can exceed `n_participants` if one
  participant repeats a trial) – kept as two separate columns since
  “repeated across participants” is what the user actually wants for
  this purpose, not raw occurrence count, which a single chatty
  participant could inflate. `sampleAlg == "check"` rows excluded by
  default (`exclude_check = TRUE`). Returns the top `n` by frequency,
  with `Center`/`Left`/`Right` columns in
  [`test.model()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/test.model.md)/[`get.hoacc()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/get.hoacc.md)-ready
  format (same first-occurrence-row extraction pattern as
  [`make.vmat()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/make.vmat.md),
  for the same reason: parsing items back out of the joined triplet-name
  string is ambiguous when item names themselves contain underscores).
  Deliberately does not itself compute a majority-vote `Answer` for the
  surfaced triplets (unlike
  [`make.vmat()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/make.vmat.md))
  – that requires first deciding on a frequency/participant threshold
  using the counts this function returns, which is exactly the judgment
  call the user was trying to make feasibility of in the first place.
  - **Real-data sanity check, not just synthetic unit tests**: ran it on
    the already-bundled `icon_triplets`, which (being a modern dataset)
    already has genuine `sampleAlg == "validation"` trials with a known
    ground truth – a strong, free correctness check, since the
    function’s own output can be compared directly against trials
    already known to be deliberately repeated. Found something genuinely
    informative in the process: `icon_triplets`’ own validation set
    turns out not to be uniformly administered to all 6 participants –
    of 40 nominal validation triplets, 20 were judged by exactly 5 of 6
    participants and 20 by only 1 (confirmed directly, not assumed, by
    checking a singleton’s raw rows: no other participant has *any*
    trial on that same 3-item set, under any `Center` assignment, so it
    isn’t a counted-separately center-swap hiding elsewhere – it’s a
    genuine one-off). `find_frequent_triplets(icon_triplets, n = 20)`
    recovers exactly those 20 five-participant triplets, confirmed via
    exact set equality against the ground truth computed independently
    from `sampleAlg == "validation"` – locked into the test suite as a
    real-data regression test, not just the synthetic small-list cases.
- **[`assign_validation_from_frequency()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/assign_validation_from_frequency.md)**
  (new) – companion to
  [`find_frequent_triplets()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/find_frequent_triplets.md),
  the other half of retrofitting a post-hoc validation set onto legacy
  data: takes its (already-thresholded) candidate output and promotes
  every matching trial’s `sampleAlg` to `"validation"`, deliberately not
  touching `sampleSet` (that’s
  [`set_validation_behavior()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/set_validation_behavior.md)’s
  job, recommended as the natural next call in the docs rather than
  duplicated here). The user explicitly asked for design recommendations
  on two open questions: what counts as “often enough,” and how to cap
  how many of one participant’s own trials get promoted. Resolved both
  by **not** owning the frequency threshold at all –
  [`find_frequent_triplets()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/find_frequent_triplets.md)
  already exists specifically so a caller inspects its `n_participants`
  column and decides a threshold deliberately (docs here suggest `>= 5`
  as a reasonable starting point, matching the ballpark this package’s
  own real bundled validation sets reach, but explicit that it depends
  on sample size) – and by adding `max_per_participant` (default `Inf`,
  i.e. no cap, since guessing a number without knowing a given study’s
  typical trial count would be worse than not capping at all) with
  concrete sizing guidance (~5-10% of a participant’s total trials)
  rather than a silently-opinionated default.
  - Three real design decisions, each resolved by reasoning about what
    the cap is *for* rather than by what was simplest to implement: (1)
    the cap counts **distinct triplets**, not raw rows – if a
    participant happened to judge the same candidate triplet twice
    (triplets are sampled independently at random in exactly the legacy
    data this targets, so repeats do happen), both trials are promoted
    together or not at all, since splitting such a pair would silently
    destroy exactly the kind of repeated-trial self-consistency data
    [`make.vmat()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/make.vmat.md)’s
    own docs call out as valuable. (2) which triplets get dropped once a
    participant exceeds the cap is controlled by **`freq_triplets`’ own
    row order** – since
    [`find_frequent_triplets()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/find_frequent_triplets.md)
    already returns candidates sorted by decreasing cross-participant
    frequency, a chatty participant who matches many candidates keeps
    the ones shared with the most *other* participants by default, which
    is also exactly what you want for the resulting validation set’s own
    majority votes to be well-supported (rather than, say, picking
    arbitrarily and ending up with a validation set that’s broad for one
    participant but thin everywhere else). (3) trials already marked
    `sampleAlg == "check"` are never promoted, checked per-row
    regardless of whether their triplet happens to appear in
    `freq_triplets` (defensive against
    `find_frequent_triplets(..., exclude_check = FALSE)` having let a
    check-trial-derived triplet into the candidate set in the first
    place).
  - Verified end-to-end, not just unit-tested in isolation: built a
    synthetic 8-participant/10-item “legacy” dataset (fully independent
    per-participant random sampling, no deliberate repetition –
    mirroring the user’s real scenario) and confirmed real
    cross-participant overlap does emerge from chance alone at this item
    count (up to 6/8 participants sharing a triplet purely
    coincidentally), that the per-participant cap is respected exactly,
    that repeated-trial pairs are never split by it, that check trials
    are never touched, and – the real litmus test – that the promoted
    result composes correctly with the existing pipeline:
    `set_validation_behavior(result, "holdout")` correctly sets
    `sampleSet <- NA` only for the newly-promoted trials, and
    `get.hoacc(emb, ..., trialtype = "validation")` runs cleanly against
    the result exactly as it would for genuine, deliberately-collected
    validation trials.
- **Real, pre-existing bug found and fixed in
  [`make.tripnames()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/make.tripnames.md)
  – broke on any dataset where `Center`/`Left`/`Right` are integer item
  indices rather than string item codes, not just a
  [`find_frequent_triplets()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/find_frequent_triplets.md)
  problem.** Surfaced when the user ran
  [`find_frequent_triplets()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/find_frequent_triplets.md)
  on a real 73-participant dataset and got
  `Error in 1:nitems : argument of length 0`. Root cause, confirmed by
  direct reproduction rather than guessed from reading the code:
  `opts <- as.matrix(tripdat[c("Left","Right")])` produces an
  **integer** matrix when `Left`/`Right` are integer columns (as they
  are in this dataset – items coded as raw numeric indices, a
  legitimate, supported way to identify items that just happened never
  to have been exercised against this function before); the next line,
  `gsub(" ","",opts)`, requires character input, and R’s implicit
  [`as.character()`](https://rdrr.io/r/base/character.html) coercion of
  a matrix argument **silently drops its `dim` attribute**, flattening
  it to a plain vector – confirmed directly with a minimal repro
  (`gsub(" ","", matrix(1:4,2,2))` returns a dim-less character vector).
  `dim(opts)[1]` then evaluates to `NULL`, and `1:NULL` is exactly what
  throws “argument of length 0”. This affects
  [`make.vmat()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/make.vmat.md)
  too (built directly on
  [`make.tripnames()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/make.tripnames.md)),
  not just the new function that happened to surface it – fixed at the
  source rather than patched locally. Fix: `mode(opts) <- "character"`
  (an in-place type coercion that preserves `dim`, unlike
  [`as.character()`](https://rdrr.io/r/base/character.html)) before the
  [`gsub()`](https://rdrr.io/r/base/grep.html) call; also made the
  `Center` coercion explicit (`as.character(tripdat$Center)`) for
  consistency, though that line was never actually broken (vectors have
  no `dim` to lose). New regression test in `test-make_tripnames.R`
  locks down the exact failure mode (multi-row integer-coded
  `Center`/`Left`/`Right`, which is what actually exercises
  `dim(opts)[1] > 1`; a single-row case wouldn’t have caught this).
  Verified against a reconstruction of the user’s actual scenario (73
  participants, 10 items, integer item codes, ~100 random trials each):
  [`find_frequent_triplets()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/find_frequent_triplets.md)
  now runs cleanly and finds real, strong cross-participant overlap (up
  to 28/73 participants sharing a triplet) – confirming the user’s
  original premise (small item counts make post-hoc validation-set
  construction from purely-random legacy sampling genuinely viable)
  actually holds once this bug is out of the way.
- **[`make.vmat()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/make.vmat.md)
  gained `n`/`nmaj`/`p`/`sig` columns**, at the user’s request, directly
  automating the manual binomial sanity-check they’d already been doing
  by hand in their own notebook (the Gabor exp1 analysis: “For 38
  participants, 25 or more agreeing with the majority is unlikely to
  occur by chance (p \< 0.04)”). `n` and `nmaj` are just the
  numerator/denominator already computed inside the existing per-triplet
  loop (`sum(thisone)`/`max(thisone)`), newly exposed as their own
  columns; `p` is the one-sided binomial p-value for observing `nmaj` or
  more agreements out of `n` under a `p = 0.5` chance-guessing null
  (`stats::pbinom(nmaj - 1, n, 0.5, lower.tail = FALSE)`, vectorized
  across all triplets after the loop rather than folded into it) – 0.5
  specifically because each judgment is a forced binary choice between
  two options, so pure guessing is 50/50 by construction, not because
  the two options are assumed equally likely to be the “true” answer for
  other reasons. `sig` is simply `p < 0.05`. Verified the p-value
  formula two ways: it matches
  `stats::binom.test(nmaj, n, p = 0.5, alternative = "greater")$p.value`
  exactly for a representative row (now locked into the test suite), and
  reproduces the user’s own by-hand number precisely
  (`pbinom(24, 38, 0.5, lower.tail = FALSE) = 0.0365`, consistent with
  their “p \< 0.04” claim). Explicitly documented in the function’s own
  roxygen that `sig` is not a meaningful filter at very low `n` – a
  triplet with only 1-2 judgments can never reach significance
  regardless of outcome (`Binomial(1, 0.5)` tops out at p = 0.5) –
  illustrated live in `overview_vignette.Rmd`‘s existing
  validation-agreement section using `icon_triplets`’ own real split (20
  triplets with a single judgment, all non-significant by construction;
  of the 20 triplets with 5 judgments each, 11 reach significance),
  verified by actually rendering the vignette rather than assuming the
  added chunk’s output. New columns are purely additive – inserted after
  the existing `pmaj` column and before the already-appended
  `Center`/`Left`/`Right` block, so the existing positional test
  (`vmat[[1]][1,3]` for `pmaj`) was unaffected and needed no change.
- **The pkgdown GitHub Actions build broke on push, right after
  `trajectory_vignette.Rmd` was committed** – found via the GitHub
  Actions REST API (not the HTML page – `gh` CLI isn’t installed here)
  after the user reported it, then reproduced and confirmed fixed with a
  real local
  `pkgdown::build_site_github_pages(new_process = FALSE, install = FALSE)`
  run rather than guessing from the log alone. Root cause:
  `_pkgdown.yml` keeps an *explicit* `articles:`/navbar listing of every
  vignette (see its own in-file comment on why – needed for the navbar
  dropdown to show individual links rather than collapsing to one
  “Articles” entry), and pkgdown’s own sitrep check treats any vignette
  missing from that list as a hard build failure (“1 vignette missing
  from index”), not a warning – a new vignette that’s never added to
  `_pkgdown.yml` breaks every subsequent push’s pkgdown build, silently
  from the vignette-author’s point of view (nothing about writing or
  committing the `.Rmd` itself fails). Fixed by adding
  `trajectory_vignette` to both the `articles.contents` list and the
  `navbar.components.articles.menu` list in `_pkgdown.yml`, positioned
  to match the order already used in `README.md`. General lesson:
  **adding a new vignette to this package means a fourth file, not
  three** – the `.Rmd` itself, `README.md`’s list, and this file’s
  `Repository layout` section were all updated for
  `trajectory_vignette.Rmd`, but `_pkgdown.yml` was missed; check all
  four together from now on whenever a vignette is added.
- **Recalibrated `recovery_sweep_params_template.yml`’s `max_epochs`
  after `0bc1af7`’s dead-tolerance fix (see that commit’s own message
  for the bug itself).** The original 60000/3000 calibration had been
  run against the *buggy* early-stopping check, so it wasn’t actually
  measuring genuine convergence – rerunning the same two worst-offending
  cells (`fit_alpha=0.1`/`0.5`, same ground-truth/triplet/fit seeds)
  against the fixed code at the real deployed
  `tol_window=3000`/`tolerance=1e-4` gave genuinely-converged stopping
  points of ~60750 and ~89670 epochs respectively – both far below the
  \>161000/200000+ the pre-fix bug had implied were needed, and close
  enough to the original 60000 ceiling to confirm that ceiling was
  already roughly right once the stopping rule actually worked.
  `max_epochs` raised to 120000 (comfortable headroom above the observed
  worst case) rather than anything near the pre-fix numbers; higher
  fitting-alphas were already converging well under 60000 in the
  original deployment (epoch-ceiling hit rate 63% at alpha=2 down to
  4.4% at alpha=Inf, vs. 90%+ at alpha\<=0.5), so this mainly gives the
  slow cells room to finish without meaningfully raising the sweep’s
  total cost. General lesson: **when a single early-stopping/convergence
  calibration run looks surprisingly bad (here: a fit needing 2-3x the
  expected epochs, or never stopping at all), check whether the
  stopping-rule code itself is doing what its own parameters claim
  before concluding the budget needs to grow to match** – the real fix
  here was one `<` becoming `< ... - tolerance`, not a bigger epoch
  budget.
- \*\*Real production bug found after an actual 50-replicate/8-alpha
  (3200-job) recovery-sweep deployment: 79% of `condor_recovery_fit.R`‘s
  companion `*_history.csv` diagnostic files came back empty, uniformly
  across every fitting alpha (79.2-79.8%), while every main result file
  was intact.\*\* Root cause: `submit_jobs_with_retry()` (in
  `condor_recovery_sweep_workflow.py`) only ever validated `output_col`
  (the main result CSV) before deciding a job succeeded – the same
  file-transfer-overload issue this function exists to catch (see the
  `condor_group_diff_workflow.py` entry above) was still silently
  destroying the history file specifically, just never detected or
  retried, since nothing checked it. Fixed by adding an
  `extra_outputs(job)` parameter (a function returning additional paths
  that must also exist and be non-empty) and passing a lambda from
  `run_fit_stage()` computing the history path via a new
  `history_output_name()` helper (mirroring `condor_recovery_fit.R`’s
  own `sub("\\.csv$", "_history.csv", ...)` naming) – a failing extra
  output now retries the whole job, since a fresh `Rscript` run
  regenerates both files together. Default behavior (no `extra_outputs`)
  is unchanged, so the other three workflows’ own copies of this
  function are unaffected – consistent with this directory’s
  self-contained-per-workflow convention.
  - **Used the surviving 21% of history files to investigate two
    follow-up questions, each informative in a different way.** (1)
    Among capped (non-converged) rows with a usable history file, the
    patience counter was at a *median of only 28%* of `tol_window` when
    training was cut off – most capped runs were not on the verge of
    stopping, consistent with these being genuinely slow-converging fits
    rather than ones that just missed the cutoff by a hair. A small
    number of specific cells (gen alpha = 20 or Inf, crossed with
    low-to-moderate fitting alphas) showed hundreds to 1000+ genuine
    small improvements across the full 120000 epochs – a noisier, slower
    convergence regime than lower-generating-alpha cells, with
    gap-growth extrapolation projecting some of these would need
    ~125000-151000 epochs to genuinely converge. (2) Replaying the exact
    early-stopping rule against the same saved histories at a *larger*
    tolerance (`analyze_recovery_history.py`, already in this directory)
    showed **all** 144 previously-capped rows would have triggered
    genuine early stopping well within the recorded 120000-epoch
    trajectory at `tolerance=5e-4` or `1e-3` (median stop epoch 59580
    / 38235) – but at a real cost: mean loss given up relative to the
    best loss ever seen jumped from ~0.00005 (at the actual
    `tolerance=1e-4`) to 0.006-0.018, a 100-400x increase, risking
    reintroducing cross-cell quality differences via premature stopping
    rather than via hitting the epoch cap. Decided against raising
    tolerance sweep-wide for this reason: the point of the whole
    exercise was making sure the matched-vs-mismatched comparison wasn’t
    contaminated by some cells being less-converged than others, and a
    looser tolerance doesn’t actually guarantee that, just changes the
    mechanism.
  - **`condor_recovery_sweep_refit_capped.py`** (new companion script, +
    `test_condor_recovery_sweep_refit_capped.py`) – built instead, to
    re-fit *only* the cells that hit a prior run’s epoch ceiling without
    converging, at a higher `max_epochs`, rather than either leaving the
    comparison contaminated or re-running the entire sweep. Infers which
    cells were capped directly from the data (the largest `epoch` value
    anywhere in `results_long.csv` is the original ceiling; any row at
    or within one epoch of it counts as capped) rather than requiring
    the old ceiling to be re-typed by hand. Reuses the original run’s
    already-simulated `stage0_simulate/` ground truth/triplets as-is (no
    resimulation) and re-derives each capped cell’s *exact* original
    `fit_seed` from its (replicate, generating alpha, fitting alpha)
    position using the identical formula `run_fit_stage()` itself uses
    (confirmed identical via a regression test that runs both code paths
    on the same synthetic config and compares the seed directly, not
    just re-implements the formula and trusts it matches) – so a refit
    cell retraces the same initialization/train-test split as its
    original attempt, just given room to actually reach its stopping
    criterion, making the result a legitimate like-for-like replacement
    rather than a different sample. Writes to a new `stage_refit/`
    directory and new
    `results_long_refit.csv`/`error_matrix_mean_refit.csv`/`error_matrix_sd_refit.csv`
    – every row from the original dataset, with just the
    previously-capped ones replaced – leaving the original outputs
    untouched for comparison/provenance. Considered (and rejected, see
    above) re-running the whole sweep with a looser tolerance instead;
    the targeted refit also costs less total compute, since it only
    touches the ~21% of cells that actually needed it rather than
    redoing everything.
- **`condor_joint_manifold_workflow.py`** (+
  `condor_joint_manifold_fit.R`, `condor_joint_manifold_update.R`,
  `joint_manifold_params_template.yml`, `README_joint_manifold.md`,
  `test_condor_joint_manifold_workflow.py`) – fourth Condor workflow,
  the Condor-scale version of the “fully rigorous” (embedding-refit)
  joint geometry+choice-model manifold idea, validated locally on real
  Gabor Experiment 3 data via a decisive LOO comparison against the
  already-in-production baseline (each person’s own individual
  embedding, standard shared alpha=1): the rigorous model won on
  held-out validation-trial log-likelihood (20/24 participants, paired
  t-test p=0.0011) with a supportive but non-significant accuracy trend
  (16/24, p=0.14) – exactly the asymmetry expected for a model whose
  advantage is in choice-model *calibration* rather than in flipping
  which option gets predicted, since accuracy is structurally
  insensitive to alpha for this Student-t/crowd-kernel family (whichever
  option has the smaller distance always has higher predicted
  probability, for any alpha). That result (plus the recovered manifold
  position independently tracking the known contrast-vs-orientation axis
  in Experiment 3) was judged sufficient evidence to justify the Condor
  investment, scoped in a planning exchange before any code was written.
  Architecture: restructured from the naive “loop over folds, and within
  each fold loop over outer iterations” shape (which would pay Condor’s
  submission/queueing latency `n_folds x n_outer` times) to loop over
  outer iterations as the only sequential axis, submitting **one Condor
  batch per iteration covering every participant’s refit at once**.
  `condor_joint_manifold_fit.R` is the second workflow here (after the
  recovery sweep) to bypass
  [`train_embedding()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/train_embedding.md)’s
  CKL-only R wrapper via `_fit_offline()`-through-reticulate,
  warm-started from each participant’s current embedding (their original
  CrowdKernel fit on iteration 1, their own previous iteration’s refit
  after that) rather than random-noise initialization, which is why
  later iterations converge faster than the first (confirmed directly
  during local validation). `condor_joint_manifold_update.R` is new
  relative to every other workflow in this directory, but not in *where*
  it runs – it was originally built to run as a local Rscript call on
  the submit node (cheap, seconds, so another Condor round-trip seemed
  not worth it), but **real-deployment feedback before the first actual
  test run** found the submit node had no R installation and uncertain
  permissions to add one, so it was moved into its own single-job Condor
  batch per outer iteration, same container image as the refit jobs
  (which already has R + tripletTools) – restoring the “no R needed on
  the submit node” property every other workflow here has. **Two real
  bugs caught during implementation, both before any Condor
  deployment**: (1) the per-job embedding-refit output was initially
  going to be written under the same filename convention
  (`person{i}.csv`) as its own `--init_embedding` input, which would
  have collided within a single job’s transfer sandbox (the same
  direction of mistake `condor_workflow.py`’s own
  transfer-path-vs-argument-basename lesson warns about, just mirrored)
  – caught by manually tracing the file-naming chain across iterations
  before testing, not by a failing test; fixed by writing refit output
  under a distinct `embedding_person{i}.csv` name and renaming to
  `person{i}.csv` locally (zero-cost) once the whole batch
  completes. (2) the SAME class of collision resurfaced when the update
  step moved into Condor: its own `--old_positions` input would
  otherwise transfer in under the same name (`positions.csv`) its
  `--output_positions` writes out – fixed by staging the previous
  iteration’s positions file under a distinct `old_positions_input.csv`
  name before transfer. Validated short of an actual cluster deployment:
  22 Python unit tests covering CSV validation, canonical item-order
  consistency checking, per-person train/test/pooled-trial file prep
  (zero-based indices, correct sampleSet split, graceful handling of a
  participant with no random trials), `submit_jobs_with_retry()` (copied
  in, same self-contained-per-workflow convention as the other three),
  and the update step’s Condor submit-file construction/output parsing
  (via a mocked `subprocess.run` standing in for
  `condor_submit`/`condor_wait`, no real cluster or Rscript needed) –
  plus a standalone functional smoke test of
  `condor_joint_manifold_update.R` itself (run directly, not through the
  orchestrator) against synthetic circular-embedding data with a
  built-in noise gradient, confirming the GPA/cmdscale/profiled-search
  pipeline runs end-to-end and recovers a position that correlates with
  the known gradient (r=-0.73). (The `condor_recovery_fit.R` seed bug
  found and fixed alongside this workflow’s first version is covered in
  its own entry below.) Only `mode: fit` (one joint estimate, no
  held-out evaluation) is implemented; `mode: loo` (the full
  leave-one-out validation mirroring the local decisive test) and
  run-resume support are both explicitly planned follow-ups, not yet
  built.
- **Found, while writing `condor_joint_manifold_fit.R` above, that
  `condor_recovery_fit.R` has had the exact same “seed never actually
  controlled a fit” bug already fixed once elsewhere in this project**
  (see the
  [`run_embeddings_from_list()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/run_embeddings_from_list.md)/[`run_group_embedding_from_list()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/run_group_embedding_from_list.md)
  entry earlier in this file): it calls `_fit_offline()` with
  `random_state = NULL` rather than the actual `seed` value, so two jobs
  with identical `--seed` only share an initial embedding and train/test
  split (both R-side, both correctly seeded) – the optimizer’s own
  internal randomness during gradient descent is never pinned down, so
  exact reruns aren’t bit-reproducible. Assessed as a reproducibility
  issue, not a validity one, for the recovery-sweep conclusions already
  drawn from it: those were established via replication across 20-50
  independent ground-truth draws specifically so that run-to-run
  variability from any source gets absorbed into the between-replicate
  spread the significance tests already account for, the bug introduces
  unbiased per-job noise (fresh process per Condor job, no shared state
  to bias a particular direction), and if anything extra uncontrolled
  noise should make a true effect *harder*, not easier, to find
  significant – so the upper/lower-triangle asymmetry finding surviving
  replication despite this is mildly reassuring rather than undermined.
  No re-run of the existing sweep was judged necessary. Fixed by
  changing `random_state = NULL` to `random_state = seed` (one line),
  matching the already-established, working pattern.
- **Real deployment crash on `condor_joint_manifold_workflow.py`’s
  actual first submit-node run (Gabor Experiment 3 data):
  `build_canonical_items()` crashed `prep_person_files()` with
  `AttributeError: 'str' object has no attribute 'keys'`.** Root cause:
  `build_canonical_items()`’s `by_worker` dict was built via
  `by_worker.setdefault(row["worker_id"], []).append(row["item"])` –
  appending just the item-name *string*, not the row – while
  `prep_person_files()` (its only caller) does
  `by_item = {r["item"]: r for r in embedding_rows_by_worker[w]}`,
  expecting each entry to be a full row dict with `dim_*` columns. No
  test caught this before the real run because every existing test
  exercised the two functions in isolation, each with hand-built inputs
  already in the shape the *other* function expects – the actual handoff
  between them (raw CSV rows all the way through to per-person embedding
  files) was never exercised end-to-end. Fixed by appending the full
  `row` instead of `row["item"]` (and deriving `first_items` from
  `r["item"]` for each row), plus a new end-to-end test chaining
  `build_canonical_items()` into `prep_person_files()` from raw rows,
  and a strengthened assertion on the existing unit test checking row
  *shape* (a dict with `dim_0` present), not just count – both confirmed
  to fail against the reverted bug and pass against the fix before
  committing. General lesson, worth remembering for this directory’s
  other orchestrators too: testing each pure function in isolation with
  inputs shaped exactly as its signature implies does not exercise
  whether an *upstream* function’s actual output matches that shape –
  that only shows up in an integration test spanning the real call
  chain, which is why this one was worth adding even though it covers no
  new branch of either function individually.
- **Second real deployment failure on
  `condor_joint_manifold_workflow.py`’s first run, right after the
  previous one was fixed: every embedding-refit job failed with
  `ModuleNotFoundError: No module named 'pandas'`, after a telltale log
  of `reticulate` downloading `uv`, a fresh `cpython-3.13` interpreter,
  and bare `numpy` from scratch.** Root cause, confirmed directly
  against `R/zzz.R`: the `"triplet-embeddings"` conda environment is
  activated by
  [`reticulate::use_condaenv()`](https://rstudio.github.io/reticulate/reference/use_python.html)
  inside tripletTools’s own `.onLoad()` – which only runs if the package
  is actually [`library()`](https://rdrr.io/r/base/library.html)-loaded,
  not merely referenced via
  `system.file(..., package = "tripletTools")`.
  `condor_joint_manifold_fit.R` never called
  [`library(tripletTools)`](https://knowledge-and-concepts-lab.github.io/tripletTools/),
  so `.onLoad()` never ran, so `reticulate` had no configured Python at
  all and fell back to auto-bootstrapping its own empty one via `uv` (a
  newer-`reticulate` fallback behavior) instead of finding the
  container’s real environment with torch/pandas/etc. already installed.
  Every *other* per-job fit script in this directory
  (`condor_recovery_fit.R`, `condor_fit.R`, `condor_group_fit.R`,
  `condor_individual_fit.R`) already calls
  [`library(tripletTools)`](https://knowledge-and-concepts-lab.github.io/tripletTools/)
  for exactly this reason – confirmed by checking all four directly, not
  assumed – this new script was simply the one place that line was
  missing. Fixed by adding the same
  `suppressPackageStartupMessages(library(tripletTools))` call used
  everywhere else in this directory.
- **`condor_joint_manifold_workflow.py` documented in
  `condor_workflows_vignette.Rmd`** as a new “Workflow 4” section (plus
  a new row in the Overview table, and a correction to “three
  independent workflows” -\> “several,” since the recovery sweep was
  already a pre-existing fourth/fifth workflow with no vignette section
  of its own – a gap this pass did not attempt to backfill, flagged
  rather than silently worked around). Covers why the workflow exists
  (the decisive log-likelihood validation on Gabor Experiment 3,
  summarized briefly with a pointer to the full write-up living outside
  the package in the lab’s own research documentation), why it’s
  iterative unlike Workflows 1-3, and the update-step-moved-into-Condor
  design decision. The full scientific write-up itself was added as a
  new section, “Does jointly estimating geometry and choice model
  improve prediction?”, in the lab’s own `triplet_choice_and_loss.Rmd`
  (outside this package, in `Simulation/ChoiceModels/`) – extending the
  existing “Variation in choice model vs geometry” section’s open
  question with the Experiment 3 decisive result (20/24 participants,
  paired $`t=3.74`$, $`p=0.0011`$ on held-out validation logLik), a
  live-computed sanity check that the recovered LOO positions correlate
  with an independent, previously-documented contrast-vs-orientation
  individual-difference axis ($`r=-0.593`$, $`p=0.0022`$, recomputed
  directly from the decisive run’s own per-participant output rather
  than reused from an earlier pilot), and a direct contrast with
  Experiment 1’s null result from the cheaper, embeddings-fixed version
  of the same check. Both documents verified by actually knitting them
  (not just inspecting source) and checking rendered numbers against the
  source computation.
- **`condor_joint_manifold_workflow.py`’s own real first deployment (30
  participants, `n_outer=2`, `mode: fit`) completed cleanly – 60/60
  refit jobs with empty `.err` files, stable beta0/beta1/positions
  across iterations, correctly-renamed embedding files – but its
  update-step output was missing the `aligned/` directory, even though
  `update.err` was empty both iterations.** Root cause, confirmed
  directly from the actual deployed `update.sub` the user pasted back:
  no explicit `transfer_output_files` was set, and HTCondor’s default
  “send back whatever’s new in the sandbox” output transfer reliably
  picks up new plain files (`positions.csv`/`beta.csv` came back fine)
  but does not reliably recurse into a newly-created *subdirectory*
  without naming it explicitly – a known HTCondor behavior, not a bug in
  `condor_joint_manifold_update.R`. Inconsequential for `mode: fit`
  (`aligned_dir` is write-only there, never read back downstream), but
  would matter for the still-unbuilt `mode: loo`. Fixed by adding an
  optional `transfer_output_files` parameter to `write_submit_file()`
  (left unset for the embedding-refit jobs, which only ever produce flat
  files) and passing `"positions.csv, beta.csv, aligned"` explicitly
  from the update step’s own submit-file call.
- **`condor_joint_manifold_workflow.py` gained resume support, motivated
  directly by its own first real production run (24 participants,
  `n_outer=8`).** That run’s per-iteration beta0/beta1 trajectory looked
  concerning at first (still growing, not decelerating) but turned out
  to have a real, specific explanation once the per-participant position
  trajectories were pulled apart: most of the sample had converged by
  iteration 6, but a coherent subgroup of 6 participants had overshot to
  an extreme position around iterations 3-5 and were still steadily
  correcting back at iteration 8 (changes of 0.05-0.07 between
  iterations 6 and 8, vs \<0.005 for the converged majority) – the
  global curve was still catching up to their correction, not diverging.
  (Bandwidth narrowing across the same iterations, initially also
  flagged as a possible overfitting signature, turned out to be roughly
  proportionate to a genuine, modest narrowing in the position
  distribution itself – checked directly via the bandwidth-to-SD ratio,
  which stayed near-constant rather than shrinking independently.) Since
  the orchestrator had no way to continue past a finished run other than
  restarting from iteration 1, extending this specific run to let that
  subgroup settle meant discarding 8 iterations of real compute. Fixed
  by making `n_outer` a total-iteration target rather than a fixed
  count: rerunning the same command (same `output_dir`) now auto-resumes
  after the last iteration with all expected outputs present
  (`iterN/positions.csv`, `iterN/beta.csv`, every
  `iterN/refit/embeddings/person{i}.csv`) rather than restarting, so
  raising `n_outer` and rerunning is how a run gets extended. Guards
  against the one real correctness risk this introduces – a resume
  silently using a *different* `triplet_data.csv`/`embeddings.csv` than
  the original run, which would misattribute every
  `person{i}.csv`-indexed position/embedding to the wrong participant –
  by recording the exact worker_id order and item order the first time
  `setup/` is built (`setup/worker_ids.txt`, `setup/item_order.txt`) and
  refusing to resume (clear error, not a silent mismatch) if a later
  invocation’s inputs would produce a different order. A new `--fresh`
  flag forces starting over regardless. 15 new unit tests (37 total)
  cover the resume-point scan (including that an incomplete iteration in
  the *middle* of a run is correctly treated as the resume point, not
  skipped over in favor of a later-looking-complete one from some
  earlier abandoned attempt) and the id-consistency check in both
  directions.
- **Real finding from the first genuine production run (24 participants,
  extended via resume to `n_outer=30`): `final_embeddings.csv` (each
  participant’s own individually-refit embedding) showed a clean,
  monotonic, textbook overfitting signature against the baseline** – a
  validation-logLik comparison against each person’s own plain
  individual embedding (standard shared alpha=1) was marginally
  *positive* at iteration 1 (+0.16, not significant) and degraded
  smoothly and monotonically to significantly *negative* by iteration 30
  (-4.32, p=0.0068), with implied alpha spanning 0.007 to 3.3 million
  across participants by the end. This looked like a direct
  contradiction of the earlier decisive LOO validation (+3.19, p=0.0011)
  until the actual discrepancy was found: that LOO test never evaluated
  a held-out participant’s own refit embedding at all – it evaluated the
  **kernel-smoothed pooled estimate** (`embed_at()`: a weighted average
  across the whole aligned pool at that participant’s own recovered
  position), since in the LOO design the held-out person’s own embedding
  was excluded from the pool entirely. Re-running the SAME overfitting
  check using that correct estimator (recomputing GPA alignment locally
  from each iteration’s own refit embeddings, so every iteration could
  be checked without needing the `aligned/` output specifically) showed
  no overfitting trend at all – the smoothed estimate beat the baseline
  at *every* iteration from 1 to 30, strongest early, dipping modestly
  through the middle (while positions were still settling), and
  re-strengthening and stabilizing from iteration ~22 onward almost
  exactly when the late position flips (see the resume-support entry
  above) resolved. **The individually-refit embedding (the workflow’s
  own main output) was never the validated artifact – the
  kernel-smoothed pooled estimate was, and the two can diverge sharply
  as a person’s own alpha becomes extreme.** Fixed by adding
  `final_smoothed_embeddings.csv`/`final_smoothed_alpha.csv` as proper
  workflow outputs (`write_smoothed_outputs()`), computed via a
  pure-Python reimplementation of `embed_at()` plus an exact
  reimplementation of R’s
  [`stats::bw.nrd0()`](https://rdrr.io/r/stats/bandwidth.html) (verified
  bit-for-bit against a real R reference value – an *approximate*
  bandwidth formula would silently use a different kernel than the one
  the R-side update step actually validated against). Requires the final
  iteration’s `aligned/` output (the thing the `transfer_output_files`
  fix a few entries up made reliable); skips with a printed note, not a
  failure, if it’s missing. 9 new tests (46 total).
- **Full 30-participant Experiment 3 production run, plus a real
  methodological question from the user that led to a genuinely useful
  decomposition.** With resume support, `n_outer=30` was run on all 30
  available Experiment 3 participants (not just the 24-participant
  quality-gated subset); the earlier 24- and 30-participant runs were
  moved to
  `GaborTriplets/joint_manifolds/condor_joint_manifold_output_ex3{,_n24}`
  to make room (see the directory-collision note below). The full-sample
  production comparison strengthened rather than weakened relative to
  n=24 (25/30 win, mean diff +3.00 nats, $`p=0.000118`$) and surfaced a
  second real non-convergence case distinct from the resume-support one:
  worker 95061’s position genuinely oscillates between two states across
  all 30 iterations (amplitude ~0.3, still moving 0.35 at the final
  transition) rather than converging, landing by coincidence within
  0.0001 of a different worker’s own genuinely-converged final position
  – caught by plotting the full trajectory, not trusting the
  final-iteration number. Separately, the full-sample run’s choice-model
  curve was dramatically more moderate than the 24-participant subset’s
  (beta1 1.76 vs. 14.56) – checked whether the six additional
  participants simply filled previously-sparse territory (they don’t;
  their positions overlap the original 24’s own range) and reported this
  as a plausible-but-unconfirmed curve-fitting-stability account rather
  than a proven mechanism.
  - **The user then asked a sharp methodological question**: since every
    participant’s own data informs both their own refit and the shared
    curve, is the production comparison’s win just self-contribution, or
    could it even be explained away – if there were no real shared
    structure, shouldn’t pooling in other participants’ data make a
    held-out prediction *worse*, not better, by the user’s own correct
    bias-variance argument? This was answered empirically, not
    rhetorically, with a controlled decomposition: four conditions (own
    vs. pooled/kernel-smoothed embedding) x (alpha fixed at 1 vs. the
    fitted smoothed-alpha curve). Alpha-smoothing alone, embedding held
    at each participant’s own refit, does nothing ($`p=0.597`$) –
    unsurprising, since accuracy is structurally alpha-invariant for
    this choice-model family and logLik barely moved either.
    **Embedding-pooling alone, alpha held fixed at 1 – the clean test of
    the user’s question – is itself a clear win** (23/30, mean diff
    +2.06 nats, $`p=0.0018`$), ruling out both the alpha-recalibration
    confound and (by the user’s own correct logic) the no-real-structure
    account. A second, fully independent check followed immediately:
    [`loo_trajectory_accuracy()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/loo_trajectory_accuracy.md)
    (already existing, no Condor run needed, no alpha component at all,
    full participant exclusion including from the 1-D axis itself) gave
    R² = 0.72, $`p=2.6\times10^{-9}`$ on the same n=30 data – about as
    decisive as this kind of test gets. Both pieces of evidence, plus
    the original small-scale full-refit LOO ($`p=0.0011`$), are
    documented in `triplet_choice_and_loss.Rmd`’s new “Is the
    embedding-pooling advantage real, or an artifact?” section, which
    closes with a concrete recommendation for future datasets: these two
    cheap checks (no Condor needed) answer the *existence* question, and
    the expensive `mode: loo` Condor workflow (one full production run
    per held-out participant) is worth its cost only when the
    *magnitude* of benefit to a genuinely new participant specifically
    needs to be trustworthy – a headline effect size, or sizing a real
    application – not as a routine step on every new dataset.
  - **A real near-miss, not a data-loss incident**: between sessions,
    the user ran the same workflow on Experiment 1 data
    (orientation-only Gabors, 38 participants, $`d=2`$) using the
    *default* `condor_joint_manifold_output` output directory – the same
    path the Experiment 3 n=30 run had used – which would have silently
    overwritten the n=30 run’s raw per-iteration data (the thing
    `triplet_choice_and_loss.Rmd`’s oscillation-trajectory figure reads
    directly from disk at knit time) had the user not already moved the
    prior results to
    `joint_manifolds/condor_joint_manifold_output_ex3{,_n24}` first.
    Caught via the harness’s own file-change notification on
    `iter30/beta.csv`, confirmed via `run_manifest.txt` showing the
    Experiment 1 inputs at that path, and resolved by updating the one
    Rmd chunk that reads the live directory (`cj_dir`) to the new
    `joint_manifolds/...` path. Worth remembering generally: this
    project’s established convention of appending a suffix to a prior
    run’s output directory (`_n24`, now `_ex3`) only protects against
    collision if it happens *before* the next run starts, not after –
    there is no in-workflow safeguard against two different datasets
    being pointed at the same default output path.
- **[`summarize_joint_estimation()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/summarize_joint_estimation.md)**
  (new) – the user, now having run this workflow on a second dataset
  (Experiment 1) and anticipating several more, asked for the
  diagnostics generated by hand above (convergence checking,
  individual-vs-smoothed comparison) to become a reusable function
  rather than a repeated manual exercise. Reads a
  `condor_joint_manifold_workflow.py` output directory directly
  (`run_manifest.txt`, `setup/worker_ids.txt`/`item_order.txt`, every
  `iterN/positions.csv`/`beta.csv`, `setup/original_embeddings/`,
  `final_embeddings.csv`,
  `final_smoothed_embeddings.csv`/`final_smoothed_alpha.csv` when
  present) and writes a self-contained Markdown report (figures as
  sibling PNGs, relative links) covering position-convergence flagging,
  the beta/bandwidth trajectory, the choice-model curve, and a 2-D/3-D
  embedding-geometry grid – all of this needs nothing beyond
  `output_dir` itself. The held-out validation comparison (the four-way
  decomposition from the discussion above, plus the
  [`loo_trajectory_accuracy()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/loo_trajectory_accuracy.md)
  confirmation) is gated on an optional `triplet_data` argument, since
  validation trials are deliberately never passed to the Condor workflow
  at all
  ([`assign_sample_sets()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/assign_sample_sets.md)’s
  `"holdout"` convention) and so cannot be recovered from `output_dir`
  alone – the original baseline embeddings, by contrast, *are* already
  saved under `setup/original_embeddings/` and need no separate
  argument. Reuses already-exported package functions
  ([`generalized_procrustes()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/generalized_procrustes.md)
  and
  [`smooth_embedding_trajectory()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/smooth_embedding_trajectory.md)
  via its explicit `query_points` argument,
  [`get.rep.dist()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/get.rep.dist.md),
  [`loo_trajectory_accuracy()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/loo_trajectory_accuracy.md))
  rather than re-deriving kernel-smoothing/GPA logic a second time; the
  profiled Student-t/crowd-kernel likelihood machinery, needed for the
  decomposition and not available anywhere else in the package (only
  duplicated across the standalone Condor R scripts, which are
  deliberately self-contained for cluster deployment – a rationale that
  doesn’t apply here, since this lives inside the package itself), is
  factored into one proper internal helper (`ckl_validation_eval()`)
  instead of being duplicated a fourth time. Verified against real data,
  not just a synthetic fixture: run on the actual Experiment 3 n=30
  output directory, every number in the generated report (the
  decomposition table, the flagged-participant table, the LOO R²)
  matched the hand-computed analysis above exactly; run on the actual
  Experiment 1 output directory with no `triplet_data` (confirming
  graceful skipping of the comparison sections) and surfaced a second,
  independently real non-convergence case worth noting for its own sake
  – a different worker whose position converges smoothly for 29
  iterations and then jumps sharply at the very last one, a distinct
  failure mode from worker 95061’s sustained oscillation above, caught
  by the same flagging logic without any manual trajectory inspection.
  `p_acc` is reported as `NA` (not a bug) whenever two compared
  conditions share the same embedding and differ only in alpha, since
  R’s own [`t.test()`](https://rdrr.io/r/stats/t.test.html) returns `NA`
  (not an error) for an exactly-zero-variance paired difference –
  documented with a footnote in the generated report rather than left to
  look like a silent failure. New test file
  `test-summarize_joint_estimation.R` (21 assertions) builds a small
  synthetic fake output directory (geometric position convergence, one
  engineered last-iteration jump) covering both the self-contained
  diagnostics and, separately, the `triplet_data`-gated comparison/LOO
  path.
- **Run live on Experiment 1 with real `triplet_data` for the first
  time, and a chain of real methodological questions that fully resolved
  a genuine open tension.** The decomposition showed a strong
  embedding-pooling win for Experiment 1 too (32/38,
  $`p=2.8\times10^{-7}`$) – on its face in tension with the fully
  out-of-sample
  [`loo_trajectory_accuracy()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/loo_trajectory_accuracy.md)
  null (R²=0.02, $`p=0.38`$) documented above. Resolved in stages, each
  tested rather than argued: (1) isolating the refit procedure itself
  from pooling (own refit, unpooled, vs. original: $`p=0.88`$, nothing)
  ruled out “refitting is just better optimization”; (2) comparing the
  position-weighted pooled estimate against a **plain,
  position-independent grand mean** (same embedding for everyone) showed
  the grand mean alone already recovers the *entire* effect (30/38 win
  on its own, $`p=1.7\times10^{-6}`$) and position-weighting adds
  nothing on top (23/38, $`p=0.53`$) – the win is pure noise reduction
  from averaging, not anything about where a given participant
  specifically sits in the pool; (3) directly checking the grand mean
  against the known orientation ground-truth circle (same construction
  as `triplet_choice_and_loss.Rmd`’s circular-geometry analysis) found a
  Procrustes correlation of 0.988 – far exceeding even the single best
  individual embedding’s own fidelity (max 0.926, median 0.745) –
  confirming the grand mean isn’t just *a* consensus, it recovers the
  true geometry almost exactly, which is exactly why pooling helps
  despite there being no real cross-participant manifold; (4) this in
  turn explains the Rmd’s own documented alpha-vs-circular-fidelity
  correlation as largely an estimation-precision artifact (lower alpha
  -\> noisier decisions -\> noisier individual embedding estimate of the
  *same* true circle, not a different true geometry), fully compatible
  with pooling denoising it away. One follow-up test came out negative,
  which was itself informative: the ~8 participants whose own individual
  embedding beats the true circle on their own held-out trials
  (`geom_mismatch` in the Rmd) were tested for whether they share a
  common alternative geometry with each other – pairwise Procrustes
  distance among them is statistically indistinguishable from a random
  same-size subset (permutation $`p=0.77`$), and a leave-one-out
  subgroup mean built from just the other outliers is the *worst* of
  four predictors tested (0.598 mean accuracy, behind even the generic
  circle’s 0.600 and the full-population grand mean’s 0.625) – these
  participants are idiosyncratically different from everyone, including
  each other, not a coherent second cluster, so no pooling scheme
  (subgroup or population-wide) has anything to offer them specifically.
- **Grand mean added as a first-class output, both in the Condor
  workflow and in
  [`summarize_joint_estimation()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/summarize_joint_estimation.md)’s
  report, directly motivated by the resolution above.**
  `write_smoothed_outputs()` (`condor_joint_manifold_workflow.py`) now
  also computes and writes `final_grand_mean_embedding.csv`
  (`grand_mean_embedding()`, pure unweighted average across the final
  iteration’s aligned pool, no kernel weighting) alongside the existing
  smoothed outputs – same `aligned/` input already being read, so
  effectively free. 2 new Python unit tests (48 total).
  [`summarize_joint_estimation()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/summarize_joint_estimation.md)’s
  decomposition grew from 5 to 7 rows: `(e) grand mean vs. (a) baseline`
  and `(c) position-weighted pool vs. (e) grand mean`, the latter being
  the direct test of “does a participant’s own recovered position add
  anything beyond plain averaging.” Reads
  `final_grand_mean_embedding.csv` when present (same
  graceful-fallback-to-local-recomputation pattern as
  `final_smoothed_*`, via
  [`generalized_procrustes()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/generalized_procrustes.md)
  on `final_embeddings`). Re-run on both real datasets to confirm the
  asymmetry predicted before writing any code: Experiment 1’s grand mean
  beats baseline decisively (30/38, $`p=1.7\times10^{-6}`$) with
  position adding nothing ($`p=0.53`$); Experiment 3’s grand mean does
  *not* reliably beat baseline at all (17/30, $`p=0.70`$, slightly
  negative), while position-weighting on top of it is itself significant
  (22/30, mean diff +2.43 nats, $`p=0.0080`$) – exactly the opposite
  pattern, confirming the comparison correctly distinguishes a dataset
  with real manifold structure from one without. Also fixed an unrelated
  latent bug surfaced while touching the test file:
  `build_fake_jm_output()`’s synthetic per-person embeddings used
  unseeded [`rnorm()`](https://rdrr.io/r/stats/Normal.html) jitter,
  making the test suite genuinely flaky (one run hit a degenerate LOO
  fold and errored inside
  [`get.hoacc()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/get.hoacc.md))
  – fixed with an explicit
  [`set.seed()`](https://rdrr.io/r/base/Random.html), confirmed by
  rerunning the suite multiple times after the fix with no recurrence.
- **`condor_workflows_vignette.Rmd`’s “Workflow 4” section brought up to
  date** rather than spinning off a new vignette –
  [`summarize_joint_estimation()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/summarize_joint_estimation.md)
  is a companion tool to this exact workflow, and this package’s
  convention is to extend a thematically-related vignette rather than
  fragment into many small ones. The section had gone stale in ways that
  were actively misleading, not just incomplete, by the time this was
  done: it still pointed readers at
  `final_embeddings.csv`/`final_positions.csv` with no warning, even
  though that’s precisely the artifact the overfitting-misdiagnosis
  finding above showed is not safe to use; its outputs table predated
  `final_smoothed_embeddings.csv`/`final_smoothed_alpha.csv`/`final_grand_mean_embedding.csv`/`aligned/`
  entirely; it said nothing about resume support; and “`mode: loo` is a
  planned follow-up” no longer matched the actual, now-settled position
  (deliberately deprioritized in favor of two cheap checks, build only
  if a magnitude claim specifically needs it – see the
  `triplet_choice_and_loss.Rmd` entry above). Fixed all four, and added
  a new “Summarizing and interpreting a run” subsection demonstrating
  [`summarize_joint_estimation()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/summarize_joint_estimation.md)
  itself, including a worked summary of the real cross-dataset asymmetry
  (grand mean alone explains Experiment 1’s pooling benefit, $`p=0.53`$
  for position on top of it; Experiment 3’s needs real
  position-weighting, $`p=0.0080`$) as the motivating example for why
  the decomposition table exists at all. Verified by actually knitting
  the vignette
  ([`knitr::knit()`](https://rdrr.io/pkg/knitr/man/knit.html), 33/33
  chunks; full HTML render via
  [`rmarkdown::render()`](https://pkgs.rstudio.com/rmarkdown/reference/render.html)
  wasn’t possible in this environment – no pandoc installed – so this is
  Markdown-level verification only, same limitation as any other render
  in this environment, not specific to this change) rather than just
  checking the source looked right.
- **`condor_joint_manifold_workflow.py` redesigned: alpha is now
  decoupled from geometric position by default, not a function of it.**
  Direct continuation of the investigation above – the user asked
  whether there was any actual rationale (computational or otherwise)
  for tying alpha to geometry, given the
  decoupled-with-proper-regularization design had just been shown to tie
  with the coupled one on the dataset where coupling mattered and to
  avoid a real liability on the other. No such rationale survived: the
  only genuine advantage of coupling was getting alpha’s regularization
  “for free” from machinery already needed for geometry, which is moot
  once the decoupled machinery is already built and validated (as it now
  was); the robustness argument (coupling can’t run away to a degenerate
  per-person estimate the way an unconstrained per-person alpha fit can)
  turned out to be an argument for *some* regularization, not for
  coupling specifically, since the decoupled-with-shrinkage version
  handles the exact same failure mode just as well. For the eventual
  paper, decoupled is also the easier story: “each participant’s alpha
  gets standard empirical-Bayes partial pooling, independent of
  geometry” needs no special justification, where “alpha is tied to the
  same manifold position as geometry” is the assumption that needed
  defending and didn’t hold up.
  - **`condor_joint_manifold_update.R`** rewritten: step 3 (position
    search) now scores candidate positions at each participant’s own
    *fixed* current alpha rather than a curve evaluated at the candidate
    position; step 4 no longer refits a shared 2-parameter curve
    (`beta0`/`beta1`) – it re-estimates each participant’s own alpha
    directly, via a per-person profiled MLE over the same bounded grid
    used throughout this investigation
    (`10^seq(log10(2e-4), log10(2e6), length.out = 140)` – avoids the
    unconstrained-optimizer runaway confirmed for participants whose own
    data is highly self-consistent, some individual estimates diverged
    past $`10^{10}`$ without a bound) followed by empirical-Bayes
    shrinkage toward a *precision-weighted* population mean (a standard
    random-effects DerSimonian-Laird estimator of the between-person
    variance net of estimation noise). The precision-weighting
    specifically matters: an initial, simpler unweighted shrinkage
    estimator was tried first and collapsed to zero between-person
    variance on both validation datasets, traced to a handful of
    poorly-identified (near-boundary) individuals distorting the
    variance estimate as much as well-identified ones – the
    precision-weighted DerSimonian-Laird version doesn’t have this
    problem, confirmed directly against both real datasets (τ² came out
    clearly nonzero, 0.124 and 1.172, where the naive estimator gave
    exactly 0 for both). `--old_beta0`/`--old_beta1` replaced by
    `--old_alpha` (a staged file path, same
    `old_positions_input.csv`-style distinct-name convention, not a
    command-line scalar, since it’s now one value per pool member);
    output is `alpha.csv` (one row per pool member: `log_alpha`,
    `alpha`, `log_alpha_raw`, `se_log_alpha`, `shrinkage_weight`
    per-person, plus `tau2`/`pop_mean_alpha`/`bandwidth` repeated
    globally) replacing `beta.csv`. Smoke-tested standalone against
    synthetic circular-embedding data (same established pattern as the
    script’s original validation) in two passes: an initial version
    using a deterministic “closer-to-truth-wins” choice rule produced
    near-saturated likelihoods (alpha pinned near the grid boundary for
    nearly everyone, bandwidth collapsed near zero) – not a code bug, a
    test-data artifact (zero simulated decision noise), fixed by
    generating choices probabilistically via the actual crowd-kernel
    rule against each participant’s own noisy embedding instead; the
    corrected version produced sensible position spread, a
    non-degenerate bandwidth, a believable mix of well- and
    poorly-identified (boundary-pinned) alpha estimates with shrinkage
    visibly pulling the latter back toward the population – and a second
    run confirmed the `--old_positions`/`--old_alpha` resume-staging
    path also works.
  - **`condor_joint_manifold_workflow.py`** updated to match: the main
    iteration loop no longer computes
    `alphas = [exp(beta0 + beta1*position) ...]` each round – it just
    passes through whatever `alphas` the previous iteration’s update
    step (or `find_resume_state()`, on a resume) already returned, since
    alpha is a direct per-person value now, not derived from a curve.
    `write_smoothed_outputs()` no longer computes or writes an alpha
    file at all (nothing position-dependent left to compute);
    `final_alpha.csv` is written directly in `main()` from the
    per-person values already in memory. `run_manifest.txt` reports
    `alpha estimation: decoupled...` and a final mean alpha instead of
    final beta0/beta1. The module-level docstring and
    `condor_joint_manifold_fit.R`’s own `--alpha` argument comment were
    both rewritten to describe the new design (the docstring was also
    stale on an unrelated point found in passing – it still said the
    update step “runs as a LOCAL Rscript call on the submit node,” which
    stopped being true when that step was moved into Condor in an
    earlier session; fixed as part of this same pass). 2 new Python unit
    tests (49 total) plus substantial rewrites to
    `TestRunUpdateStep`/`TestIterationIsComplete`/`TestFindResumeState`/`TestWriteSmoothedOutputs`
    for the new `alpha.csv`-based signatures.
  - **[`summarize_joint_estimation()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/summarize_joint_estimation.md)**
    updated in step: `read_joint_manifold_run()` now builds an
    `alpha_mat` (n participants x n_outer, mirroring `positions_mat`)
    and a small `alpha_diag_traj` (per-iteration
    `tau2`/`pop_mean_alpha`/`bandwidth`) from each iteration’s
    `alpha.csv`, instead of a single `beta_traj`; reads
    `final_alpha.csv` (renamed from `final_smoothed_alpha.csv`, now a
    direct per-person pass-through with no position dependence). New
    `flag_unstable_joint_alpha()` gives alpha its own independent
    convergence check (log-alpha space, same window/threshold convention
    as position’s). The “Choice-model curve across the manifold” report
    section (a fitted `alpha(t)` line, which no longer exists) is
    replaced by a purely descriptive final-alpha-vs-position scatter
    plot that assumes no relationship. **Real bug caught before this
    shipped**, found by running the updated function against a real
    *old-format* run (predates this redesign, so it has no
    `iterN/alpha.csv` or `final_alpha.csv` at all):
    [`graphics::matplot()`](https://rdrr.io/r/graphics/matplot.html) on
    an all-`NA` `alpha_mat` (`log10(NA)` throughout) failed with “need
    finite ‘ylim’ values,” an unhandled crash rather than a graceful
    skip. Fixed with a `has_alpha_traj <- !all(is.na(run$alpha_mat))`
    guard around both new alpha plots and the alpha-flagging table,
    printing an explanatory note instead – the same “skip gracefully,
    don’t fail the whole report” pattern `write_smoothed_outputs()`’s
    own missing-`aligned/` handling already established, now applied to
    this new failure mode too. Verified end-to-end against that same
    real old-format directory after the fix: runs cleanly, correctly
    reports “no `iterN/alpha.csv` found… predates alpha being decoupled
    from position,” and the held-out comparison’s
    `estimate_shrunk_alpha()` fallback (triggered since
    `final_alpha.csv` doesn’t exist either) reproduced numbers
    consistent with the by-hand validation earlier in this
    investigation. Test fixture (`build_fake_jm_output()`) updated to
    write per-iteration `alpha.csv` (varying by worker, not constant –
    an initial constant-alpha version produced degenerate zero-variance
    paired differences once combined with the fixture’s
    already-identical toy embeddings/trials, triggering
    [`t.test()`](https://rdrr.io/r/stats/t.test.html)’s “data are
    essentially constant” error) and gained a new `oscillate_alpha_last`
    parameter, independent of `oscillate_last` (position), exercising
    the new independent alpha-convergence check; 33 assertions total (up
    from 24), including new direct tests of
    `flag_unstable_joint_alpha()` and `estimate_shrunk_alpha()`.
  - **Documentation**: `inst/condor/README_joint_manifold.md` and
    `vignettes/condor_workflows_vignette.Rmd`’s Workflow 4 section both
    rewritten for the decoupled design – updated outputs tables
    (`alpha.csv`/`final_alpha.csv` replacing
    `beta.csv`/`final_smoothed_alpha.csv`), the iteration-steps
    description, the resume-state description, and a new subsection in
    each (*Does alpha need to be tied to geometry?* / the README’s own
    top-of-file note) explaining the finding and pointing to
    `triplet_choice_and_loss.Rmd` for the full comparison. Verified by
    re-knitting the vignette end-to-end (33/33 chunks, no errors).
- **Real production incident: a HELD Condor job stalled an overnight
  `condor_joint_manifold_workflow.py` deployment completely, with no
  automatic recovery.** `condor_q -held` showed
  `Error from slot1_11@e2472.chtc.wisc.edu: ... invalid mount config for type "bind": bind source path does not exist: /cvmfs`
  – a transient broken Docker/CVMFS mount on one specific bad CHTC
  execute node, unrelated to the job’s own code, data, or container
  image. The real problem wasn’t the hold itself (a plain
  `condor_release` fixes it, since the matchmaker reassigns the job to a
  different slot rather than retrying the same bad one) – it’s that
  **every** orchestrator’s `submit_and_wait()` called a single blocking
  `condor_wait` with no timeout, and `condor_wait` only returns once
  every job in its log has *terminated or been removed*; a held job does
  neither until a human intervenes. So the driver’s blocking wait sat
  there all night with no way to notice or recover on its own, distinct
  from (and not covered by) `submit_jobs_with_retry()`, which only
  checks for missing/empty output *after* `condor_wait` already returned
  – it never fires if the wait itself never returns.
  - Fixed identically across **all five** orchestrators
    (`condor_workflow.py`, `condor_group_diff_workflow.py`,
    `condor_individual_embeddings_workflow.py`,
    `condor_recovery_sweep_workflow.py`,
    `condor_joint_manifold_workflow.py` – same
    self-contained-per-workflow duplication convention as every other
    shared fix here, e.g. `submit_jobs_with_retry()` itself):
    `submit_and_wait()` now parses the cluster id out of
    `condor_submit`‘s own stdout, then polls with
    `condor_wait -wait 120 <log>` in a loop instead of one open-ended
    call. On each timeout it checks
    `condor_q <cluster> -held -af ProcId HoldReason` and auto-releases
    (`condor_release`) anything found held, up to 3 releases per job
    before giving up with a clear error naming the job and its hold
    reason – rather than either hanging forever or failing instantly on
    a merely-transient hold. New
    `HELD_JOB_MAX_RELEASES`/`HELD_JOB_POLL_SECONDS` constants and a
    `held_jobs_in_cluster()` helper, duplicated into each file the same
    way. 4 new tests in `test_condor_joint_manifold_workflow.py` (53
    total; all 93 tests across the other four workflows’ own suites pass
    unchanged, confirming the signature/behavior change – `condor_wait`
    now called with extra args, an occasional new
    `condor_q`/`condor_release` call – doesn’t break any existing mocked
    test, none of which asserted the exact `condor_wait` argument list,
    only `cmd[0]`). `README_joint_manifold.md`, `README_group_diff.md`,
    `README_individual_embeddings.md`, `README_recovery_sweep.md`, and
    `condor_workflows_vignette.Rmd`’s shared troubleshooting section (a
    new “A job goes held mid-run” subsection, mirroring the existing
    “empty output” one’s structure) all updated to describe the new
    auto-release behavior instead of telling the reader to notice and
    release a held job manually.
- **Real bug found in
  [`get.combined()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/get.combined.md):
  an all-digit `worker_id` column is silently read back as numeric,
  dropping leading zeros.** Surfaced while helping the user add a
  [`write.csv()`](https://rdrr.io/r/utils/write.table.html) step to
  `Simulation/ManifoldEstimation/ManifoldEstimation.Rmd` (outside this
  package, a research notebook) so freshly-regenerated simulated
  triplets could round-trip through
  [`get.combined()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/get.combined.md)
  without a stale CSV in between. `simulate.participant()`’s random
  10-digit `worker_id` strings have about a 96% chance across 30
  participants that at least one starts with `0`;
  [`read.csv()`](https://rdrr.io/r/utils/read.table.html)’s default type
  inference reads an all-digit-looking column as numeric regardless, so
  e.g. `"0733092758"` came back as the numeric `733092758` – same root
  cause, same failure signature (IDs silently merged/dropped on
  mismatch) as the already-documented, already-fixed Python-side bug in
  `compute_embeddings.py::process_all_workers()` above, just
  independently present on the R/CSV-reading side of this shared,
  exported function. Confirmed directly: `unique(tmp$worker_id)` after a
  plain [`read.csv()`](https://rdrr.io/r/utils/read.table.html) showed
  several IDs 1-2 digits short of the expected 10. Fixed by forcing
  `worker_id` (and `item`, for the `eflag=TRUE` embeddings case, same
  risk in principle) to character via a targeted `colClasses` argument –
  reads the header first to build a named `colClasses` vector only for
  whichever of those two columns are actually present, leaving every
  other column’s type auto-detected as before. New regression test
  (`test-get_combined.R`) locks down the exact failure mode: a
  2-participant synthetic CSV with one ID starting with `0`, asserting
  the read-back ID stays a full 10-character string and its 2 rows
  aren’t split off into an unmatched, dangling entry. Full 241-block
  package test suite re-run and confirmed unaffected.
- \*\*[`summarize_joint_estimation()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/summarize_joint_estimation.md)‘s
  embedding-geometry grid was silently double-smoothing, visibly
  flattening real structure.\*\* Found after the user re-ran the
  decoupled-alpha workflow on Experiment 1
  (`GaborTriplets/joint_manifold_exp1`, 38 participants, n_outer=30) and
  noticed the geometry-grid panels didn’t recover the known circular
  arrangement of the orientation stimuli nearly as cleanly as the
  original always-fit-at-alpha=1 individual embeddings did. Root cause:
  `smoothed_source <- run$final_smoothed_embeddings %||% run$final_embeddings`
  preferred the already-pooled/kernel-smoothed file (the same preference
  used correctly everywhere else in the report, since the raw per-person
  refit is the known-to-overfit artifact – see the “real finding” entry
  above), but the grid itself then calls
  [`smooth_embedding_trajectory()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/smooth_embedding_trajectory.md)
  a *second* time on whatever it picked, to interpolate across a grid of
  query positions that generally aren’t any real participant’s actual
  position. When the smoothed file is present (every current-format
  run), that means smoothing twice with the same kernel/bandwidth –
  close to convolving a Gaussian with itself, which compounds to an
  effective bandwidth roughly sqrt(2)x larger than intended –
  over-flattening exactly the position-dependent geometric structure the
  plot exists to show. Fixed by always building the grid from the raw
  `run$final_embeddings` directly (renamed `smoothed_source` -\>
  `geometry_source`), a single smoothing pass, matching the only case
  where this worked correctly before (an old-format run with no
  `final_smoothed_embeddings.csv` at all). Verified by re-rendering both
  real datasets’ reports: Experiment 1’s grid now shows a clean,
  well-formed ring with the orientation color gradient running smoothly
  around it from `t=-0.15` onward, matching what the original
  per-individual alpha=1 fits recovered – the one remaining ragged panel
  (`t=-0.59`, the extreme low tail) is expected, not a smoothing
  artifact, since that’s the sparse-data boundary region where the one
  position-unstable participant (`67e08871...`, flagged in the same
  report’s convergence table) sits. All 33 existing tests pass unchanged
  (they only assert the PNG file is written, not its content). Purely a
  visualization fix – no statistics in the decomposition table or
  [`loo_trajectory_accuracy()`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/loo_trajectory_accuracy.md)
  check were ever affected, since neither reads
  `final_smoothed_embeddings` through this code path.
