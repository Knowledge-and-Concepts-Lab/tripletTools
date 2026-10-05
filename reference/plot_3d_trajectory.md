# Plot a 3-D embedding at one point along a smoothed trajectory

Draws a 3-D scatterplot of the kernel-weighted embedding at one query
point of a
[`smooth_embedding_trajectory`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/smooth_embedding_trajectory.md)
result, with a density-style strip along the bottom of the plot showing
`effective_n` across every query point, a red marker at the query point
currently shown, and (optionally) small black dots marking real
participants' own positions along the same axis – so a sequence of calls
at increasing `loc` (e.g. to build an animation, as in
`gifski::save_gif()`) can be read both as "what the representation looks
like here" and "how much real data actually supports this point."
[`plot_2d_trajectory`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/plot_2d_trajectory.md)
is the 2-D equivalent, built on base graphics instead of scatterplot3d,
with the same argument conventions.

## Usage

``` r
plot_3d_trajectory(
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
  [`smooth_embedding_trajectory`](https://knowledge-and-concepts-lab.github.io/tripletTools/reference/smooth_embedding_trajectory.md)
  (a list with `query_points`, `embeddings`, `effective_n`, among
  others). Each embedding must have exactly 3 columns.

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
  [`scatterplot3d`](https://rdrr.io/pkg/scatterplot3d/man/scatterplot3d.html),
  overriding this function's own defaults for any name also used
  internally (e.g. `angle`, `grid`, `box`) – see *Overriding plot
  appearance* below.

## Value

The `scatterplot3d` object, returned invisibly (as
[`scatterplot3d`](https://rdrr.io/pkg/scatterplot3d/man/scatterplot3d.html)
itself returns it), in case the caller wants to add further elements to
the same plot via its `$xyz.convert` coordinate-conversion function.

## Overriding plot appearance

`pcols`/`bcols`/`pch`/`cex.symbols` are kept as their own named
arguments because each has specific `NULL`-default handling (e.g.
recycling a single black color across every item). Everything else
[`scatterplot3d`](https://rdrr.io/pkg/scatterplot3d/man/scatterplot3d.html)
accepts can be set or overridden through `...` – internally, a list of
this function's own defaults (`angle`, `mar`, axis limits, tick marks,
etc.) is merged with `list(...)` via
[`modifyList`](https://rdrr.io/r/utils/modifyList.html) (so `...` values
win on any name clash) and passed to
[`scatterplot3d::scatterplot3d`](https://rdrr.io/pkg/scatterplot3d/man/scatterplot3d.html)
via [`do.call`](https://rdrr.io/r/base/do.call.html) – so e.g.
`angle = 60` or `grid = FALSE` can be passed directly without this
function needing its own named argument for every possibility.

## Examples

``` r
if (FALSE) { # \dontrun{
repdist <- get.rep.dist(icon_emb_ind)
pos <- cmdscale(repdist, k = 1)[, 1]
traj <- smooth_embedding_trajectory(icon_emb_ind, pos, n_query = 50)
plot_3d_trajectory(traj, pos = pos, loc = 25)
} # }
```
