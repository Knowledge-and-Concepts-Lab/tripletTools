# Standardise a legacy triadic comparison dataset

Reads a single CSV file from a legacy triplet experiment and converts it
to the standard column format used by this package. Unrecognised or
missing columns are derived where possible from the data that are
present; see the **Column mappings** section below for full details. Two
output files are written alongside the input: a standardised data CSV
and a stimulus-level mapping CSV.

## Usage

``` r
read_legacy(input_file)
```

## Arguments

- input_file:

  Character. Path to the input CSV file.

## Value

A list returned invisibly with two elements:

- `data_file`:

  Path of the written standardised data CSV (input filename with
  `_v2025.csv` suffix).

- `levels_file`:

  Path of the written stimulus-level mapping CSV (input filename with
  `_2025_levels.csv` suffix).

## Output columns

- `p_id`:

  Character participant identifier.

- `Center`:

  Character label of the target (reference) stimulus.

- `Left`:

  Character label of the left-hand choice stimulus.

- `Right`:

  Character label of the right-hand choice stimulus.

- `Answer`:

  Character label of the chosen stimulus.

- `head`:

  Integer (0-indexed) factor code for `Center`, ordered alphabetically
  across all unique stimuli in `Center`, `Left`, and `Right`.

- `winner`:

  Integer factor code for `Answer`, using the same ordering as `head`.

- `loser`:

  Integer factor code for the unchosen option, using the same ordering
  as `head`.

- `RT`:

  Numeric reaction time. `NA` if not present in the input.

- `sampleAlg`:

  Character sampling algorithm label: `"random"`, `"check"`,
  `"validation"`, `"uncertainty"`, or `NA`.

- `sampleSet`:

  Character set label: `"train"` or `"test"`.

## Column mappings

Input column names are matched case-insensitively and ignoring
punctuation.

- Participant ID (`p_id`):

  Recognised input names: `sessionID`, `session_ID`, `puid`,
  `Participant.ID`, `worker_id`, `sub_id`, `pid`. If none are found,
  participants are assigned sequential IDs (`"P1"`, `"P2"`, ...).

- Center:

  Recognised input names: `Center`, `Target`.

- Left:

  Recognised input names: `Left`, `Option1`.

- Right:

  Recognised input names: `Right`, `Option2`.

- winner / loser:

  Recognised input names: `winner` / `primary` and `loser` /
  `alternate`. Derived from `Answer`, `Left`, and `Right` when absent.

- sampleAlg:

  Recognised input names: `sampleAlg`, `AlgSample`. Values are recoded:
  `"Random"` → `"random"`; `"Test"` → `"validation"`; `"check"` →
  `"check"`; `"uncertainty"` → `"uncertainty"`. Filled with `NA` when
  absent.

- sampleSet:

  Recognised input names: `sampleSet`, `Alg.Label`, `TrnTest`. When
  absent, 10\\ randomly assigned to `"test"` and the remainder to
  `"train"` (seed `2025`).

## Examples

``` r
if (FALSE) { # \dontrun{
result <- clean_triadic_comparisons("data/triplets.csv")
print(paste("Wrote:", result$data_file, "and", result$levels_file))
} # }
```
