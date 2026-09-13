"""
Realistic intrabar path generator.

An M1 bar is expanded into a zig-zag random walk that:
  * starts at O, ends at C
  * touches exactly L and H (in the order implied by bar direction)
  * never leaves [L, H]
  * has a step count driven by that bar's tick volume

This matters enormously for stop-and-reverse / trailing scalpers: the naive
O-H-L-C 4-point model lets a trade capture a bar's entire range in one clean
monotonic move, which massively inflates results.
"""
import random


def _bridge(a, b, n, lo, hi, sigma, rng):
    """Brownian bridge a->b in n steps, clamped to [lo,hi]. Returns pts after a."""
    if n <= 1:
        return [b]
    out = []
    cur = a
    for i in range(1, n):
        # pull toward b, proportional to remaining steps
        rem = n - i + 1
        drift = (b - cur) / rem
        cur = cur + drift + rng.gauss(0.0, sigma)
        if cur < lo:
            cur = lo + (lo - cur) * 0.3
            if cur > hi:
                cur = hi
        elif cur > hi:
            cur = hi - (cur - hi) * 0.3
            if cur < lo:
                cur = lo
        out.append(cur)
    out.append(b)
    return out


def bar_path(o, h, l, c, tickvol, rng, max_steps=48, min_steps=6, noise=0.28):
    """Return list of bid prices walking through the bar."""
    rng_hl = h - l
    if rng_hl <= 0:
        return [o, c]

    n = int(min(max_steps, max(min_steps, tickvol / 8.0)))
    # visit order: down-first for bullish bars, up-first for bearish bars
    legs = [(o, l), (l, h), (h, c)] if c >= o else [(o, h), (h, l), (l, c)]

    # split steps proportionally to leg length
    lens = [abs(b - a) for a, b in legs]
    tot = sum(lens) or 1.0
    counts = [max(2, int(round(n * x / tot))) for x in lens]

    path = [o]
    for (a, b), k in zip(legs, counts):
        sigma = rng_hl * noise / (k ** 0.5)
        path.extend(_bridge(a, b, k, l, h, sigma, rng))
    return path
