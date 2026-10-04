#' Triplet data for 58 color patches
#'
#' A list containing triplet similarity judgments from 46 participants on 58
#' color patches spanning color space. Participants judged which of two
#' option patches was more similar in color to a reference patch. These
#' triplets were used to compute embeddings of the 58 patches separately for
#' each participant (`color_emb_ind`) as well as a single group embedding
#' (`color_emb_group`).
#'
#' @format ## `color_triplets`
#' A named list, each containing a dataframe with 11 columns:
#' \describe{
#'   \item{head, winner, loser}{Integer indices for items in a given triplet.}
#'   \item{worker_id}{Random identifier for each participant.}
#'   \item{rt}{Response time on triplet (in milliseconds).}
#'   \item{Center}{The target item, given as a hex color code (e.g. `"#5E2B3A"`).}
#'   \item{Left, Right}{The option items appearing on the left and right, same coding.}
#'   \item{Answer}{The option item chosen by the participant.}
#'   \item{sampleAlg}{The algorithm used to sample the item.}
#'   \item{sampleSet}{Which set the sampled item belongs to.}
#' }
#'
#' @details
#'
#' Each element of the list contains the triplet data for one participant
#' in the study. Rows of a dataframe correspond to a single trial. The
#' elements of the full list are named by the random participant ID number.
#'
#' Item codes (`Center`/`Left`/`Right`/`Answer`) are hex color strings, which
#' also serve directly as plotting colors for the corresponding patch (see
#' `color_lab`).
#'
#' Each triplet can be sampled in one of three ways indicated by sampleAlg:
#' 1. _random_: Sampled randomly with uniform probability from all triplets.
#' 2. _validation_: Sampled randomly from a fixed, pre-specified set of possible triplets.
#' 3. _check_: Sampled from a small set of items where the answer is obvious,
#'  used to check attention and data quality.
#'
#' The column `sampleSet` indicates how the triplet is to be used in computing
#' and evaluating embeddings (`"train"`/`"test"`; `NA` for check trials).
#'
#' @source Zimnicki et al., presented at the Annual Meeting of the Cognitive
#'   Science Society. \url{https://escholarship.org/uc/item/8778p3t3}
"color_triplets"
