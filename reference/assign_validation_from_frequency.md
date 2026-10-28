# Promote frequently-repeated triplets to validation trials

Companion to
[`find_frequent_triplets`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/find_frequent_triplets.md):
given a candidate set of triplets (its output, or a threshold-filtered
subset of it), sets `sampleAlg <- "validation"` on every matching trial
in `triplet_list` – retroactively turning triplets that happened to be
judged by many participants into genuine validation trials, for legacy
data collected before this package's `sampleAlg == "validation"`
convention existed.

## Usage

``` r
assign_validation_from_frequency(
  triplet_list,
  freq_triplets,
  max_per_participant = Inf,
  verbose = TRUE
)
```

## Arguments

- triplet_list:

  Named list of per-participant triplet data frames, the same object
  passed to
  [`find_frequent_triplets`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/find_frequent_triplets.md).

- freq_triplets:

  A data frame with a `triplet` column identifying which triplets to
  promote – normally the (optionally filtered) return value of
  [`find_frequent_triplets`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/find_frequent_triplets.md).
  All thresholding on "how often is often enough" happens there (via its
  own `n`/ `min_participants` arguments, or by filtering its output
  yourself) – this function does no frequency filtering of its own, it
  just applies whichever candidate set it's given. Row order matters
  when `max_per_participant` is finite – see Details.

- max_per_participant:

  Integer (or `Inf`, the default). Caps how many *distinct* candidate
  triplets any one participant can have promoted to `"validation"` – see
  Details for why this is a per-triplet cap, not a per-row one, and how
  it interacts with `freq_triplets`' row order.

- verbose:

  Logical. Print a short summary (how many triplets/trials were
  promoted, and any participants with none at all)? Default `TRUE`.

## Value

`triplet_list` with `sampleAlg` updated for promoted trials; a list of
the same length, names, and row order as the input. No other column is
touched – in particular, `sampleSet` is left exactly as it was. Call
[`set_validation_behavior`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/set_validation_behavior.md)
on the result afterward (`mode = "holdout"` is almost always what you
want – see Details) to actually exclude the newly-promoted trials from
training and model selection.

## Details

**Why no frequency threshold lives here.**
[`find_frequent_triplets`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/find_frequent_triplets.md)'s
own documentation already makes the case for deciding "how often is
often enough" by inspecting its `n_participants` column, rather than
picking a number blind. A reasonable starting point for data with enough
participants to support it: require at least 5 participants per
candidate triplet, the same ballpark this package's own bundled real
validation sets reach (see `icon_triplets`) – but this depends heavily
on total sample size and should be checked against the actual
distribution of `n_participants` in your data
(`table(find_frequent_triplets(triplet_list, n = Inf)$n_participants)`
is a quick way to see it) rather than assumed.

**Why `max_per_participant` exists and defaults to `Inf`.** Every trial
promoted to `"validation"` is (assuming you then call
[`set_validation_behavior`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/set_validation_behavior.md)
with `mode = "holdout"`, as recommended above) one fewer trial available
to train and test that participant's own embedding. A participant who
happens to have judged many of the candidate triplets could lose a
large, disproportionate share of their data this way with no cap in
place. There's no universal right number – it depends on how many trials
each participant completed in total – so the default is `Inf` (no cap)
rather than a guessed value, with the recommendation to set it
deliberately, e.g. to roughly 5-10\\

**Why the cap counts distinct triplets, not rows.** A participant who
happened to judge the same candidate triplet twice (triplets are usually
sampled independently at random in exactly the legacy data this function
targets, so repeats do happen) has both of those trials promoted
together or not at all – the cap is never allowed to split a repeated
triplet's trials apart, since
[`make.vmat`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/make.vmat.md)'s
own documentation notes repeated validation trials are useful for
assessing a participant's self-consistency, and keeping only one half of
such a pair would quietly throw that away.

**Why row order in `freq_triplets` controls which triplets get dropped
under the cap.** When a participant's matches exceed
`max_per_participant`, the triplets kept are whichever appear *earliest*
in `freq_triplets`.
[`find_frequent_triplets`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/find_frequent_triplets.md)
already returns its rows sorted by decreasing frequency, so by default
this means: when a participant must lose some candidate triplets to the
cap, the ones kept are those shared with the most other participants –
which is also what you want for the resulting validation set's own
majority votes to be well-supported. Passing a `freq_triplets` you
reordered yourself changes this priority accordingly.

Trials already marked `sampleAlg == "check"` are never promoted,
regardless of whether their triplet appears in `freq_triplets`.

## See also

[`find_frequent_triplets`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/find_frequent_triplets.md)
for building `freq_triplets`;
[`set_validation_behavior`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/set_validation_behavior.md)
for the usual next step.

## Examples

``` r
if (FALSE) { # \dontrun{
freq <- find_frequent_triplets(legacy_triplets, n = Inf, min_participants = 5)
legacy_triplets <- assign_validation_from_frequency(
  legacy_triplets, freq, max_per_participant = 30
)
legacy_triplets <- set_validation_behavior(legacy_triplets, mode = "holdout")
} # }
```
