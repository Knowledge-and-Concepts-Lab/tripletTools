# Find the most frequently repeated triplets across participants

Given a list of per-participant triplet data frames, finds the triplets
judged by the largest number of distinct participants, treating a
triplet as the same trial regardless of which option appeared on the
left or the right (but not regardless of which item was the
reference/`Center` item – that's a different question being asked, not
the same trial mirrored).

## Usage

``` r
find_frequent_triplets(
  triplet_list,
  n = 50,
  min_participants = 1,
  exclude_check = TRUE
)
```

## Arguments

- triplet_list:

  Named list of per-participant triplet data frames (the package's
  standard `Center`/`Left`/`Right`/`Answer`/ `worker_id` shape, e.g.
  `icon_triplets`).

- n:

  Integer. Number of triplets to return, ranked by the number of
  distinct participants who judged them (ties broken by total trial
  count, then alphabetically by the triplet's own name – see Details).
  Default 50.

- min_participants:

  Integer. Only triplets judged by at least this many distinct
  participants are eligible to be returned, even if fewer than `n` such
  triplets exist. Default 1 (no filtering).

- exclude_check:

  Logical. Drop `sampleAlg == "check"` rows (attention-check trials)
  before counting, if a `sampleAlg` column is present. Default `TRUE`.

## Value

A data frame with one row per selected triplet, sorted by decreasing
frequency, with columns:

- triplet:

  The triplet's unique code, from
  [`make.tripnames`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/make.tripnames.md)
  (`Center_Left_Right`, with `Left`/`Right` in a fixed,
  left/right-independent order).

- Center, Left, Right:

  The triplet's items, in the format
  [`test.model`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/test.model.md)/[`get.hoacc`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/get.hoacc.md)
  expect – so the result can be used directly as (or merged into) a
  `Center`/`Left`/`Right`/`Answer`-shaped triplet data frame once an
  `Answer` is assigned (e.g. a majority vote, the same way
  [`make.vmat`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/make.vmat.md)
  computes one for genuine validation trials).

- n_participants:

  Number of distinct participants (by `worker_id`) who judged this
  triplet at least once.

- n_trials:

  Total number of trials judging this triplet, pooled across all
  participants – can exceed `n_participants` if any one participant
  judged the same triplet more than once.

## Details

This is for retrofitting a post-hoc validation set onto legacy data
collected before this package's `sampleAlg == "validation"` convention
existed, where every triplet was instead sampled independently at random
for each participant. Because triplets are drawn from a combinatorially
large pool (an `m`-item study has `m * choose(m - 1, 2)` distinct
`Center`/{`Left`, `Right`} combinations), real cross-participant overlap
is only likely to turn up when `m` is small and/or the number of trials
per participant is large relative to that pool – check that
`n_participants` actually reaches a usable minimum for the top triplets
returned here before treating them as a real validation set, rather than
assuming it from the item count alone.

Once a usable set of frequent triplets is found, a natural next step is
to compute each one's majority-vote answer across the participants who
judged it (the same construction
[`make.vmat`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/make.vmat.md)
uses for genuine validation trials) and treat that as its `Answer` for a
held-out evaluation set. This function only finds and counts the
candidate triplets – it does not compute majority votes itself, since
doing so meaningfully requires first deciding on a frequency/participant
threshold using the counts returned here.

Triplet identity is determined by
[`make.tripnames`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/make.tripnames.md),
the same convention
[`make.vmat`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/make.vmat.md)
uses for genuine validation trials: two trials are the same triplet if
they share the same `Center` and the same unordered pair of
`Left`/`Right` items. A trial with the same three items but a different
`Center` is a different question (a different reference item), not the
same triplet mirrored, and is counted separately.

## Examples

``` r
freq <- find_frequent_triplets(icon_triplets, n = 10)
freq
#>              triplet Center  Left Right n_participants n_trials
#> 1  fdmob_fdfow_pnhob  fdmob fdfow pnhob              5        5
#> 2  fdmob_fdmow_fdmyb  fdmob fdmow fdmyb              5        5
#> 3  fdmow_fdmyw_fnfyw  fdmow fdmyw fnfyw              5        5
#> 4  fdmow_fnmyw_pdhnb  fdmow fnmyw pdhnb              5        5
#> 5  fdmyb_fdfob_pdhos  fdmyb fdfob pdhos              5        5
#> 6  fdmyb_fnfyb_pdcns  fdmyb fnfyb pdcns              5        5
#> 7  fnfyb_fdmyb_pdcnb  fnfyb fdmyb pdcnb              5        5
#> 8  fnmob_fdmob_fnmyb  fnmob fdmob fnmyb              5        5
#> 9  fnmyb_fdfob_pdcns  fnmyb fdfob pdcns              5        5
#> 10 fnmyb_pnhnb_pnhos  fnmyb pnhnb pnhos              5        5
```
