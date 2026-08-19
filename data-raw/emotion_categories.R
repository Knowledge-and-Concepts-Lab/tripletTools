## code to prepare `emotion_categories` dataset: Shaver et al. (1987) basic
## emotion category assignments for the 213 emotion words in
## `emotion_triplet_embedding`/`emotion_bge_embedding`.
##
## 78 of the 213 words are labeled "Absent" -- words Shaver et al. did not
## end up assigning to a basic-emotion category. "Surprise" has only 3
## words, too few for reliable cross-validated classification. Both are
## kept in the bundled data (rather than pre-filtered out) so the vignette
## can show that filtering step explicitly; see the emotion-word vignette
## example for the recommended 132-word, 5-category subset used there.

raw <- read.csv("data-raw/EmotionWords_Shaver213.csv", stringsAsFactors = FALSE)

stopifnot(
  identical(raw$word, rownames(emotion_triplet_embedding)),
  !anyNA(raw$word),
  !anyNA(raw$category),
  !anyDuplicated(raw$word)
)

emotion_categories <- data.frame(
  category = factor(raw$category),
  row.names = raw$word
)

usethis::use_data(emotion_categories, overwrite = TRUE)
