## code to prepare `emotion_triplet_embedding` and `emotion_bge_embedding`
## datasets: a 4D triplet-based embedding of 213 emotion words (Shaver et al.,
## 1987) alongside a BAAI/bge-m3 language-model embedding of the same words.
##
## The raw bge-m3 embedding is 1024-dimensional, but with only 213 items its
## centered coordinate matrix cannot have rank above 212 -- so it is rotated
## onto its own top 212 principal components before shipping. This is a
## lossless change of basis for every Procrustes-based comparison in this
## package (Procrustes fit is invariant to orthogonal rotation of either
## input), and cuts the on-disk size by roughly 80% (353KB vs 1.7MB as raw
## doubles). See the verification checks below.

trip_raw <- read.csv("data-raw/shaver_triplet_embedding.csv", stringsAsFactors = FALSE)
bge_raw  <- read.csv("data-raw/shaver_bge_m3.csv", stringsAsFactors = FALSE)

stopifnot(
  identical(trip_raw$item, bge_raw$word),
  !anyNA(trip_raw),
  !anyNA(bge_raw[, grepl("^dim_", names(bge_raw))]),
  !anyDuplicated(trip_raw$item)
)

# --- Triplet-based embedding (already low-dimensional; kept as-is) --------

emotion_triplet_embedding <- trip_raw[, grepl("^dim_", names(trip_raw))]
row.names(emotion_triplet_embedding) <- trip_raw$item

# --- BGE-M3 embedding: rotate onto its own lossless (item-count-bounded) --
# --- principal components, instead of shipping the full 1024 raw dims ----

bge_mat <- as.matrix(bge_raw[, grepl("^dim_", names(bge_raw))])
row.names(bge_mat) <- bge_raw$word

true_rank <- matrix_rank(bge_mat)  # 212 for 213 items (n - 1), not 1024
pca <- prcomp(bge_mat, center = TRUE, scale. = FALSE)

emotion_bge_embedding <- as.data.frame(pca$x[, seq_len(true_rank)])
colnames(emotion_bge_embedding) <- sprintf("pc_%03d", seq_len(true_rank))
row.names(emotion_bge_embedding) <- row.names(bge_mat)

# --- Verify the PCA rotation lost (essentially) nothing relevant to any ---
# --- Procrustes-based comparison, before shipping the reduced version ----

fidelity <- procrustes_spectral_ceiling(emotion_bge_embedding, bge_mat)
cat(sprintf(
  "PCA truncation fidelity check: procrustes_spectral_ceiling(reduced, full) = %.6f (should be ~1)\n",
  fidelity
))
stopifnot(fidelity > 0.9999)

usethis::use_data(emotion_triplet_embedding, overwrite = TRUE)
usethis::use_data(emotion_bge_embedding, overwrite = TRUE)
