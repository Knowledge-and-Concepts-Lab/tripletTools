# Successor representation of a weighted adjacency matrix

Converts a weighted adjacency (transition-weight) matrix into a
Successor Representation: a discounted sum of expected future
visitation, in the style of reinforcement-learning
successor-representation models.

## Usage

``` r
successor_matrix(W, gamma = 0.5, pseudocount = 0)
```

## Arguments

- W:

  Square numeric matrix (or object coercible to one) of non-negative
  transition weights, rows = "from" items, columns = "to" items.

- gamma:

  Discount factor, `0 <= gamma < 1`. Larger values weight longer-range
  paths more heavily. Default `0.5`.

- pseudocount:

  Non-negative constant added to every entry of `W` before
  row-normalizing, to avoid zero-weight rows or to smooth sparse graphs.
  Default `0` (no smoothing).

## Value

A named list with two elements:

- `successor`:

  The successor matrix `S = (1 - gamma) * solve(diag(n) - gamma * P)`,
  with row and column names taken from `W`.

- `transition`:

  The row-normalized transition matrix `P` used to compute `S`.

## Details

`W` is first row-normalized (after adding `pseudocount`) to a transition
matrix `P`, so that each row of `P` sums to 1. The successor matrix `S`
then gives, for each pair of items, the discounted expected number of
times item `j` would be visited starting a random walk from item `i` and
following `P`, summed over an infinite horizon and weighted by `gamma`
per step: `S = (1 - gamma) * sum_t gamma^t P^t`. At `gamma = 0` only the
`t = 0` term survives and `S` is the identity matrix (no diffusion
beyond an item itself); as `gamma` increases, `S` incorporates
progressively longer paths through the graph, and as `gamma` approaches
1 every row of `S` converges toward the graph's stationary distribution,
reflecting global rather than local structure.

Turning a similarity or adjacency graph into a successor matrix is one
way to derive an embedding-like representation that captures multi-step
relational structure rather than only direct pairwise similarity.

## Examples

``` r
# A small weighted graph over four items
W <- matrix(
  c(0, 1, 1, 0,
    1, 0, 0, 1,
    1, 0, 0, 1,
    0, 1, 1, 0),
  nrow = 4, byrow = TRUE,
  dimnames = list(letters[1:4], letters[1:4])
)
result <- successor_matrix(W, gamma = 0.5)
result$successor
#>            a          b          c          d
#> a 0.58333333 0.16666667 0.16666667 0.08333333
#> b 0.16666667 0.58333333 0.08333333 0.16666667
#> c 0.16666667 0.08333333 0.58333333 0.16666667
#> d 0.08333333 0.16666667 0.16666667 0.58333333
```
