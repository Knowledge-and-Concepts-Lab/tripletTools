# Plot a 2-D embedding at one point along a smoothed trajectory

The 2-D equivalent of
[`plot_3d_trajectory`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/plot_3d_trajectory.md),
built on base graphics
([`plot`](https://rdrr.io/r/graphics/plot.default.html)) instead of
scatterplot3d, with the same argument conventions: a density-style strip
along the bottom showing `effective_n` across every query point, a red
marker at the query point currently shown, and (optionally) small black
dots marking real participants' own positions along the same axis.

## Usage

``` r
plot_2d_trajectory(
  traj,
  pos = NULL,
  loc,
  pcols = NULL,
  bcols = NULL,
  pch = NULL,
  cex.symbols = 1,
  ...
)
```

## Arguments

- traj:

  The full return value of
  [`smooth_embedding_trajectory`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/smooth_embedding_trajectory.md).
  Each embedding must have exactly 2 columns (use
  [`plot_3d_trajectory`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/plot_3d_trajectory.md)
  for 3-D ones).

- pos:

  Numeric vector or `NULL`. Participants' own positions along the same
  1-D axis `traj` was built from (e.g. the same `positions` passed to
  [`smooth_embedding_trajectory`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/smooth_embedding_trajectory.md)).
  When supplied, each one is drawn as a small black dot along the bottom
  density strip, at the position implied by linearly mapping
  `range(traj$query_points)` onto the strip's rendered extent – this
  assumes `traj$query_points` are evenly spaced (the default when
  [`smooth_embedding_trajectory`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/smooth_embedding_trajectory.md)
  generates its own grid) and is only an approximation otherwise. A
  position outside `range(traj$query_points)` is still plotted, which
  can place it outside the visible plot area. Default `NULL` omits the
  dots.

- loc:

  Integer index into `traj$query_points`/`traj$embeddings` – which query
  point to display. Must be between 1 and `length(traj$query_points)`.

- pcols, bcols:

  Point fill/border colors, recycled across items as usual (see
  [`scatterplot3d`](https://rdrr.io/pkg/scatterplot3d/man/scatterplot3d.html)'s
  `bg`/ `color`). Default `NULL` for both uses plain black for every
  item.

- pch:

  Point character. Default `NULL` uses `21` (a filled circle with a
  separately-colorable border, matching the `pcols`/`bcols` split).

- cex.symbols:

  Point size. Default `1`.

- ...:

  Additional arguments passed to
  [`plot`](https://rdrr.io/r/graphics/plot.default.html), overriding
  this function's own defaults for any name also used internally (e.g.
  `asp`, `main`) – same mechanism as
  [`plot_3d_trajectory`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/plot_3d_trajectory.md)'s
  `...` (see its *Overriding plot appearance* section): this function's
  own defaults are merged with `list(...)` via
  [`modifyList`](https://rdrr.io/r/utils/modifyList.html) and dispatched
  via [`do.call`](https://rdrr.io/r/base/do.call.html).

## Value

`NULL`, invisibly
([`plot`](https://rdrr.io/r/graphics/plot.default.html) itself returns
nothing meaningful to pass along).

## Examples

``` r
if (FALSE) { # \dontrun{
repdist <- get.rep.dist(icon_emb_ind)
pos <- cmdscale(repdist, k = 1)[, 1]
traj <- smooth_embedding_trajectory(icon_emb_ind, pos, n_query = 50)
plot_2d_trajectory(traj, pos = pos, loc = 25)
} # }
```
