# Clean raw choice strings from jsPsych CSV output

Strips file-path prefixes, surrounding brackets, quotes, and the file
extension from the `choices` column as exported by jsPsych. The result
is a plain comma-separated string of bare stimulus names suitable for
downstream splitting and matching.

## Usage

``` r
process_choices(choices, extension = ".png")
```

## Arguments

- choices:

  Character vector of raw choice strings, e.g.
  `"[\"assets/stimuli/cat.png\",\"assets/stimuli/dog.png\"]"`.

- extension:

  Character. File extension to strip, including the leading dot.
  Default: `".png"`.

## Value

Character vector of the same length as `choices`, with brackets, quotes,
path prefixes, and the extension removed.

## Examples

``` r
raw <- c(
  "[\"assets/stimuli/cat.png\",\"assets/stimuli/dog.png\"]",
  "[\"resources/apple.png\",\"resources/banana.png\"]"
)
process_choices(raw)
#> [1] "cat,dog"      "apple,banana"
# [1] "cat,dog"   "apple,banana"

```
