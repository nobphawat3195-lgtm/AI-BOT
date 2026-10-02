"""Build a control price series: same bar-by-bar volatility & spread as the real
data, but the sequence of returns is shuffled -> no genuine momentum structure."""
import random, datetime, copy

def shuffled_series(bars, seed=0):
    rng = random.Random(seed)
    # bar "shapes" (o->c return, and h/l offsets) get reshuffled onto a new walk
    shapes = []
    for b in bars:
        shapes.append((b['c']-b['o'], b['h']-max(b['o'],b['c']), min(b['o'],b['c'])-b['l'],
                       b['sp'], b['tv']))
    rng.shuffle(shapes)
    out=[]; px=bars[0]['o']
    for b, (dc, up, dn, sp, tv) in zip(bars, shapes):
        o=px; c=o+dc
        h=max(o,c)+up; l=min(o,c)-dn
        out.append(dict(t=b['t'], o=round(o,2), h=round(h,2), l=round(l,2), c=round(c,2),
                        sp=sp, tv=tv))
        px=c
    return out
