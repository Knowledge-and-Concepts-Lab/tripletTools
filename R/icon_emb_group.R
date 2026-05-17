#' Group embedding data for 32 icon images of faces and buildings
#'
#' This dataset contains embedding coordinates from a triplet study using 32 icon images
#' showing faces and buildings. All stimuli vary in age (old/young) and time (day/night).
#' Faces also vary in gender and race; places vary in size and kind (house/church).
#' Five participants were asked to judge which option was more similar to the referent without
#' further instruction. The object is a single data frame containing 3d embedding coordinatwes
#' computed from the training trials for all participants.
#'
#' @format ## `icon_emb_group`
#' A data frame with 32 rows (items) and columns as follows:
#' \describe{
#'   \item{dim_0, dim_1, dim_2}{First, second and third dimensions of the embedding.}
#'   \item{worker_id}{Set to group since this is a group embedding}
#'   \item{item}{Name of the stimulus item at that embedding location.}
#'   \item{path}{path to stimulus file}
#' }
#'
#' @details
#' The letters in the stimulus identifier indicate features of the corresponding
#' icon as follows: face/place, day/night, female/male/church/house, old/young, black/white/big/small.
#'
#' @source Colon et al., in preparation.
"icon_emb_group"
