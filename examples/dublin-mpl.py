"""
dublin-mpl.py — matplotlib styling that matches the Dublin Beamer theme.

    import dublin_mpl as dublin
    dublin.use()

    fig, ax = plt.subplots(figsize=(6.2, 2.9))
    ax.plot(x, y, color=dublin.SERIES[0])
    ax.fill_between(x, lo, hi, color=dublin.SERIES[0], alpha=0.16, lw=0)
    dublin.save(fig, "figures/event-study.png")

Figures are drawn at the size they will appear on the slide, so the type in
the figure ends up the same size as the type around it. A chart drawn at 12
inches and shrunk to 6 arrives with labels half the size of the caption.
"""

import matplotlib as mpl
import matplotlib.pyplot as plt
from matplotlib.colors import LinearSegmentedColormap

# ---------------------------------------------------------------- palette

NAVY    = "#04204C"
BLUE    = "#0056A4"
BLUE_LT = "#9FC4E0"
GREEN   = "#61B77C"
INK     = "#212529"
MUTED   = "#6C757D"
RULE    = "#D8E0E6"
WASH    = "#F2F6F9"

# In order of use. Stop at three if you can: past that a legend is doing the
# work a label on the line would do better. There is no sixth colour on
# purpose -- a chart needing six series is a chart that wants splitting.
SERIES = [NAVY, GREEN, BLUE, MUTED, BLUE_LT]

SEQUENTIAL = ["#EDF2F7", "#BED6E9", "#7FAED4", "#206CB0", "#024081", "#04204C"]
# Navy one way, green the other, through the wash. Both ends are the deck's
# own hues, so a signed map sits with the slide rather than importing a warm
# colour the theme never uses.
DIVERGING = ["#04204C", "#2E6193", "#9FC4E0", "#F4F6F9",
             "#A8D6B6", "#4E9E68", "#1E5733"]

cmap_sequential = LinearSegmentedColormap.from_list("dublin_seq", SEQUENTIAL)
cmap_diverging = LinearSegmentedColormap.from_list("dublin_div", DIVERGING)


def use(base_size: float = 13.0) -> None:
    """Apply the theme's drawing conventions to matplotlib's defaults."""
    mpl.rcParams.update({
        "font.size": base_size,
        "xtick.labelsize": base_size - 2,
        "ytick.labelsize": base_size - 2,
        "axes.titlesize": base_size - 1,
        "axes.labelsize": base_size,
        # Type in the palette, not in matplotlib's black
        "text.color": NAVY,
        "axes.labelcolor": NAVY,
        "axes.edgecolor": MUTED,
        "xtick.color": MUTED,
        "ytick.color": MUTED,
        # Two spines, not four. The data is the figure.
        "axes.spines.top": False,
        "axes.spines.right": False,
        "axes.linewidth": 1.1,
        "axes.grid": False,
        "legend.frameon": False,
        "figure.facecolor": "white",
        "axes.facecolor": "white",
        "savefig.facecolor": "white",
        "axes.prop_cycle": mpl.cycler(color=SERIES),
        "lines.linewidth": 2.2,
        "lines.markersize": 5.5,
    })


def band(ax, x, lo, hi, color=NAVY, **kw):
    """A confidence band: the line's own colour, well faded, no edge."""
    return ax.fill_between(x, lo, hi, color=color, alpha=0.16, lw=0, **kw)


def rule(ax, y=0.0):
    """A zero line, in the theme's hairline colour."""
    return ax.axhline(y, color=RULE, lw=1.2, zorder=0)


def marker(ax, x):
    """A dashed vertical marker for an event date or a threshold."""
    return ax.axvline(x, color=MUTED, lw=1.1, ls=(0, (4, 3)), zorder=0)


def save(fig, path, dpi=200):
    fig.tight_layout()
    fig.savefig(path, dpi=dpi)
    plt.close(fig)
