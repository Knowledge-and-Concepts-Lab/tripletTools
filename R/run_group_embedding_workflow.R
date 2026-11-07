#' Standard group-embedding workflow: dimensionality, final fit, choice-model refit
#'
#' Chains together the three steps of this package's standard recipe for
#' producing a production group embedding:
#' \enumerate{
#'   \item \strong{Dimensionality.} \code{\link{estimate_dimensionality}} searches
#'     over \code{dims} under the crowd-kernel choice model (\eqn{\alpha = 1}),
#'     selecting \code{best_d} via its one-standard-error rule.
#'   \item \strong{Final fit.} \code{\link{run_group_embedding_from_list}} is
#'     called \code{n_restarts_final} times at \code{best_d}, each from an
#'     independent random initialization, keeping whichever restart achieves
#'     the lowest test loss. This is a dedicated refit, not a reuse of one of
#'     the embeddings fitted during step 1 -- see the \emph{Why a dedicated
#'     final fit} section below.
#'   \item \strong{Choice-model refit.} \code{\link{estimate_group_alpha}}
#'     takes the winning final fit as a warm start and coordinate-ascends
#'     between re-estimating the Student-t/crowd-kernel shape \eqn{\alpha} and
#'     refitting the embedding under it, using held-out
#'     \code{sampleAlg == "validation"} trials to profile \eqn{\alpha}.
#' }
#'
#' @section Why a dedicated final fit:
#' Steps 1 and 3 both already exist as standalone functions; what this
#' wrapper adds is the final-fit step in between, plus the glue to chain all
#' three.  Reusing the single best-loss embedding that happened to come out
#' of step 1's (dimension, restart) grid would tie the production embedding
#' to whatever restart budget that grid spent per dimension -- necessarily
#' small, since it is multiplied across every dimension in \code{dims}.  A
#' dedicated final-fit step is a one-time cost (not multiplied by a
#' dimension grid), so it is the cheapest place in the whole workflow to
#' spend extra restart budget on the one embedding that is actually used
#' downstream.  This mirrors \code{inst/condor/condor_workflow.py}'s existing
#' three-stage Condor architecture (dimensionality search, learning curve,
#' final embedding fit), which already treats the final fit as a separate
#' stage rather than a reuse of a dimensionality-search artifact; the Condor
#' workflow's own final stage (\code{condor_fit.R}, \code{stage == "final"})
#' gained the same \code{n_restarts}-and-keep-lowest-loss logic for the same
#' reason.
#'
#' Picking the lowest test loss among \code{n_restarts_final} restarts is a
#' mild "best of k" selection, so that restart's own test loss is a slightly
#' optimistic estimate of its true generalization loss -- the same kind of
#' optimism inherent in selecting \code{best_d} itself.  This is a standard,
#' usually small effect with \code{k} in the single digits, not something
#' this function tries to correct for.
#'
#' @section Dimension estimation and the test set:
#' \code{estimate_dimensionality}'s internal \code{sampleSet == "test"} pool
#' is never touched during dimensionality search (see that function's own
#' \emph{Internal test set and restart variability} section) -- it is
#' reserved for this function's step 2, exactly as
#' \code{\link{run_group_embedding_from_list}} uses it.  That means the same
#' \code{sampleSet} train/test split, assigned once upstream (e.g. via
#' \code{\link{assign_sample_sets}}), is reused consistently across all three
#' steps of this workflow -- the dimensionality search is not re-randomizing
#' or resampling that top-level split per restart; the resampling it does do
#' (see \code{estimate_dimensionality}'s \code{internal_test_frac}) happens
#' entirely within the \code{"train"} pool, matched across every dimension
#' for a given restart so dimension comparisons stay apples-to-apples.
#'
#' @param triplet_list A named list of data frames, one per participant, as
#'   returned by \code{\link{get.combined}}.  Must contain a usable
#'   \code{sampleSet} column (see \code{\link{assign_sample_sets}}) and, if
#'   \code{refit_alpha = TRUE}, genuine \code{sampleAlg == "validation"}
#'   trials (see \code{\link{estimate_group_alpha}}).
#' @param dims Integer vector of dimensionalities to evaluate in step 1.
#'   Default \code{1:8}.
#' @param n_restarts_dim Random restarts per dimension in step 1, forwarded to
#'   \code{\link{estimate_dimensionality}}'s \code{n_restarts}.  Default
#'   \code{10L}.
#' @param n_restarts_final Independent random restarts for the dedicated final
#'   fit in step 2; the restart with the lowest test loss is kept.  Default
#'   \code{5L}.  Each restart uses seed \code{seed + (r - 1) * 1000}, the same
#'   restart-seed formula used throughout this package's Condor workflows.
#' @param internal_test_frac,max_epochs,tolerance,tol_window,device,norm_penalty
#'   Forwarded to \code{\link{estimate_dimensionality}} (step 1) and
#'   \code{\link{run_group_embedding_from_list}} (step 2); \code{max_epochs},
#'   \code{tolerance}, \code{tol_window}, \code{device}, and
#'   \code{norm_penalty} are also forwarded to \code{\link{estimate_group_alpha}}
#'   (step 3).  \code{internal_test_frac} is only used by step 1 (see that
#'   function's own documentation).
#' @param seed Base integer seed.  Step 1 receives it directly; step 2's
#'   restarts derive \code{seed + (r - 1) * 1000} from it; step 3 receives it
#'   directly as its own \code{seed}.
#' @param geometry Either \code{"euclidean"} (default) or \code{"sphere"},
#'   forwarded to steps 1 and 2.  \code{\link{estimate_group_alpha}} (step 3)
#'   does not currently support \code{geometry = "sphere"}; this function
#'   errors clearly if \code{geometry = "sphere"} and \code{refit_alpha = TRUE}
#'   rather than silently refitting a Euclidean embedding when a spherical one
#'   was requested. Set \code{refit_alpha = FALSE} to use spherical geometry
#'   for steps 1-2 alone.
#' @param radius Sphere radius when \code{geometry = "sphere"}.  Default \code{1}.
#' @param best_d_norm_penalty Forwarded to \code{\link{estimate_dimensionality}}.
#'   Default \code{NULL} (equal to \code{norm_penalty}).
#' @param refit_alpha Logical; if \code{TRUE} (default), run step 3.  Set to
#'   \code{FALSE} to stop after the final fit (step 2) -- e.g. when
#'   \code{triplet_list} has no \code{sampleAlg == "validation"} trials yet.
#' @param max_outer,tol_log_alpha,alpha_grid Forwarded to
#'   \code{\link{estimate_group_alpha}} (step 3); ignored if
#'   \code{refit_alpha = FALSE}.
#' @param verbose Logical; print a progress line at the start of each step and
#'   for each final-fit restart.  Default \code{TRUE}.  Forwarded to
#'   \code{\link{estimate_dimensionality}} and \code{\link{estimate_group_alpha}}.
#'
#' @return A named list with four elements:
#' \describe{
#'   \item{\code{dimensionality}}{The full return value of
#'     \code{\link{estimate_dimensionality}} (step 1): \code{results} and
#'     \code{summary}.}
#'   \item{\code{best_d}}{The selected dimensionality (smallest \code{d} with
#'     \code{summary$best_d == TRUE}).}
#'   \item{\code{final_fit}}{The winning restart's return value from
#'     \code{\link{run_group_embedding_from_list}} (step 2): \code{embedding},
#'     \code{loss}, \code{history} -- the crowd-kernel (\eqn{\alpha = 1})
#'     production embedding at \code{best_d}.}
#'   \item{\code{refit}}{\code{NULL} if \code{refit_alpha = FALSE}; otherwise
#'     the return value of \code{\link{estimate_group_alpha}} (step 3):
#'     \code{embedding} (the refit geometry), \code{alpha}, \code{log_alpha},
#'     \code{ci}, \code{history}.}
#' }
#'
#' @export
#'
#' @examples
#' \dontrun{
#' out <- run_group_embedding_workflow(
#'   triplet_list     = icon_triplets,
#'   dims             = 1:6,
#'   n_restarts_dim   = 5L,
#'   n_restarts_final = 5L
#' )
#' out$best_d
#' out$final_fit$embedding       # crowd-kernel (alpha = 1) production embedding
#' out$refit$embedding           # choice-model-refit embedding
#' out$refit$alpha               # estimated choice-model shape parameter
#'
#' # Stop after the final fit (e.g. no validation trials available yet)
#' out2 <- run_group_embedding_workflow(icon_triplets, refit_alpha = FALSE)
#' out2$refit  # NULL
#' }
run_group_embedding_workflow <- function(triplet_list,
                                          dims = 1:8,
                                          n_restarts_dim = 10L,
                                          n_restarts_final = 5L,
                                          internal_test_frac = 0.1,
                                          max_epochs = 50000L,
                                          tolerance = 1e-4,
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
                                          alpha_grid = 10^seq(log10(2e-4), log10(2e6), length.out = 140),
                                          verbose = TRUE) {
  geometry <- match.arg(geometry)
  if (geometry == "sphere" && refit_alpha) {
    stop("estimate_group_alpha() (step 3) does not currently support geometry = \"sphere\". ",
         "Set refit_alpha = FALSE to use spherical geometry for steps 1-2 alone.")
  }

  if (verbose) {
    message(sprintf("[run_group_embedding_workflow] Step 1/3: estimating dimensionality over d in %s...",
                     paste(range(dims), collapse = ":")))
  }
  dim_est <- estimate_dimensionality(
    triplet_list        = triplet_list,
    dims                = dims,
    n_restarts          = n_restarts_dim,
    internal_test_frac  = internal_test_frac,
    max_epochs          = max_epochs,
    tolerance           = tolerance,
    tol_window          = tol_window,
    device              = device,
    seed                = seed,
    verbose             = verbose,
    group               = TRUE,
    geometry            = geometry,
    radius              = radius,
    norm_penalty        = norm_penalty,
    best_d_norm_penalty = best_d_norm_penalty
  )

  best_d_rows <- which(dim_est$summary$best_d)
  if (length(best_d_rows) == 0L) {
    stop("estimate_dimensionality() did not flag any dimension as best_d -- inspect dim_est$summary directly.")
  }
  best_d <- dim_est$summary$d[best_d_rows[1]]
  if (verbose) message(sprintf("[run_group_embedding_workflow] Selected best_d = %d", best_d))

  if (verbose) {
    message(sprintf("[run_group_embedding_workflow] Step 2/3: final fit at d = %d (%d restart%s)...",
                     best_d, n_restarts_final, if (n_restarts_final == 1L) "" else "s"))
  }
  best_fit <- NULL
  best_restart <- NA_integer_
  for (r in seq_len(n_restarts_final)) {
    restart_seed <- seed + (r - 1L) * 1000L
    fit_r <- run_group_embedding_from_list(
      triplet_list = triplet_list,
      d            = best_d,
      max_epochs   = max_epochs,
      tolerance    = tolerance,
      tol_window   = tol_window,
      device       = device,
      seed         = restart_seed,
      geometry     = geometry,
      radius       = radius,
      norm_penalty = norm_penalty
    )
    if (verbose) {
      message(sprintf("[run_group_embedding_workflow]   final-fit restart %d/%d: seed=%d, test loss=%.6f",
                       r, n_restarts_final, restart_seed, fit_r$loss))
    }
    if (is.null(best_fit) || fit_r$loss < best_fit$loss) {
      best_fit <- fit_r
      best_restart <- r
    }
  }
  if (verbose && n_restarts_final > 1L) {
    message(sprintf("[run_group_embedding_workflow] Keeping final-fit restart %d/%d (lowest test loss = %.6f)",
                     best_restart, n_restarts_final, best_fit$loss))
  }

  refit <- NULL
  if (refit_alpha) {
    if (verbose) message("[run_group_embedding_workflow] Step 3/3: joint choice-model/embedding refit...")
    refit <- estimate_group_alpha(
      triplet_list  = triplet_list,
      warm_start    = best_fit$embedding,
      max_epochs    = max_epochs,
      tolerance     = tolerance,
      tol_window    = tol_window,
      seed          = seed,
      device        = device,
      norm_penalty  = norm_penalty,
      max_outer     = max_outer,
      tol_log_alpha = tol_log_alpha,
      alpha_grid    = alpha_grid,
      verbose       = verbose
    )
  }

  list(
    dimensionality = dim_est,
    best_d         = best_d,
    final_fit      = best_fit,
    refit          = refit
  )
}
