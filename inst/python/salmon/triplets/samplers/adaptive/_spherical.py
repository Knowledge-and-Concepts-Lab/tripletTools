"""
Spherical (and circular, the ``d=2`` case) variants of the triplet noise
models in ``_noise_models.py``.

Points are constrained to the surface of a ``(d-1)``-sphere of radius
``radius`` embedded in R^d, rather than living freely in Euclidean space.

Distances are computed as ordinary (chordal) squared Euclidean distance
between the constrained points — *not* re-derived as great-circle geodesic
distance. For two points on a common sphere, chordal distance
``c = 2 r sin(theta / 2)`` is a strictly monotonic function of the geodesic
distance ``r * theta`` for ``theta`` in ``[0, pi]`` (the only range that
arises, since great-circle distance between two points never exceeds the
sphere's half-circumference). Every noise model here (CKL, STE, ...) is
itself monotonic in its two distance arguments, so training on chordal vs.
geodesic distance induces the *same* triplet ordering and the *same*
optimum embedding (up to the reparameterization) — chordal distance is just
numerically nicer (no ``arccos``, whose gradient blows up as points
approach each other or antipodes). Geodesic distances can always be
recovered afterward from a fitted embedding via
``r * arccos(clip(dot(a, b) / r**2, -1, 1))`` for interpretation.

Everything else is reused unchanged: each noise model's ``_probs``/``losses``
method only ever sees a pair of scalar dissimilarities (``win2``, ``lose2``)
and has no notion of which metric produced them, so constraining the
embedding to a sphere (and reusing the inherited Euclidean ``_get_dists``)
is enough to turn any of them into a spherical variant.
"""
import torch

from salmon.triplets.samplers.adaptive._noise_models import (
    CKL,
    GNMDS,
    SOE,
    STE,
    TSTE,
    Logistic,
)

_EPS = 1e-6


class SphereMixin:
    """
    Mixin that constrains a ``TripletDist`` subclass's embedding to the
    surface of a sphere (see module docstring for why chordal distance is
    used for training rather than re-deriving geodesic distance).

    Must be listed before the noise-model class it's mixed into, e.g.
    ``class SphericalCKL(SphereMixin, CKL): pass``.

    Parameters
    ----------
    radius : float, optional (default: 1.0)
        Radius of the sphere the embedding is constrained to.
    """

    def __init__(self, n=None, d=2, radius=1.0, random_state=None, **kwargs):
        super().__init__(n=n, d=d, random_state=random_state, **kwargs)
        self.radius = radius
        with torch.no_grad():
            self._embedding.data = self._to_sphere(self._embedding.data)

    def _to_sphere(self, X):
        norms = torch.norm(X, dim=1, keepdim=True).clamp_min(_EPS)
        return self.radius * X / norms

    def pre_step(self):
        """
        Project the raw (ambient-space) gradient onto the tangent space of
        the sphere at each point, by zeroing its radial component. Called
        after ``loss.backward()`` but before the optimizer step, so the
        optimizer only ever sees the Riemannian gradient — without this,
        the radial component (which just rescales a point's norm, something
        ``project()`` immediately undoes anyway) dominates Adadelta's
        per-coordinate step-size adaptation and the fit stalls.
        """
        with torch.no_grad():
            grad = self._embedding.grad
            if grad is None:
                return
            x = self._embedding.data
            radial = (torch.sum(grad * x, dim=1, keepdim=True) / (self.radius ** 2)) * x
            grad -= radial

    def project(self):
        """
        Re-project the embedding back onto the sphere (the retraction step).
        Called after every gradient step by
        :class:`~salmon.triplets.samplers.adaptive.Embedding`.
        """
        with torch.no_grad():
            self._embedding.data = self._to_sphere(self._embedding.data)


class SphericalSTE(SphereMixin, STE):
    pass


class SphericalTSTE(SphereMixin, TSTE):
    pass


class SphericalCKL(SphereMixin, CKL):
    """The crowd kernel noise model, with points constrained to a sphere."""


class SphericalGNMDS(SphereMixin, GNMDS):
    pass


class SphericalSOE(SphereMixin, SOE):
    pass


class SphericalLogistic(SphereMixin, Logistic):
    pass
