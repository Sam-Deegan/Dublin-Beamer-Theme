## dublin-ggplot.R — ggplot2 styling that matches the Dublin Beamer theme.
##
##   source("dublin-ggplot.R")
##   ggplot(df, aes(t, beta)) +
##     geom_ribbon(aes(ymin = lo, ymax = hi), fill = dublin$navy, alpha = 0.16) +
##     geom_line(colour = dublin$navy, linewidth = 0.8) +
##     theme_dublin()
##   ggsave("figures/event-study.png", width = 6.2, height = 2.9, dpi = 200)
##
## Save at the size the figure will appear on the slide. A chart drawn at 12
## inches and shrunk to 6 arrives with labels half the size of the caption.

library(ggplot2)

dublin <- list(
  navy    = "#04204C",
  blue    = "#0056A4",
  blue_lt = "#9FC4E0",
  green   = "#61B77C",
  ink     = "#212529",
  muted   = "#6C757D",
  rule    = "#D8E0E6",
  wash    = "#F2F6F9"
)

## In order of use. Stop at three if you can: past that a legend is doing the
## work a label on the line would do better. There is no sixth colour on
## purpose -- a chart needing six series is a chart that wants splitting.
dublin_series <- c(dublin$navy, dublin$green, dublin$blue,
                   dublin$muted, dublin$blue_lt)

dublin_sequential <- c("#EDF2F7", "#BED6E9", "#7FAED4",
                       "#206CB0", "#024081", "#04204C")

## Navy one way, green the other, through the wash. Both ends are the deck's
## own hues, so a signed map sits with the slide.
dublin_diverging <- c("#04204C", "#2E6193", "#9FC4E0", "#F4F6F9",
                      "#A8D6B6", "#4E9E68", "#1E5733")

theme_dublin <- function(base_size = 13) {
  theme_minimal(base_size = base_size) +
    theme(
      text             = element_text(colour = dublin$navy),
      axis.text        = element_text(colour = dublin$muted,
                                      size = base_size - 2),
      axis.title       = element_text(colour = dublin$navy),
      axis.line        = element_line(colour = dublin$muted, linewidth = 0.4),
      axis.ticks       = element_line(colour = dublin$muted, linewidth = 0.3),
      ## Two lines, not a grid. The data is the figure.
      panel.grid.major = element_blank(),
      panel.grid.minor = element_blank(),
      panel.background = element_rect(fill = "white", colour = NA),
      plot.background  = element_rect(fill = "white", colour = NA),
      strip.text       = element_text(colour = dublin$navy, face = "bold",
                                      hjust = 0, size = base_size - 1),
      strip.background = element_blank(),
      legend.key       = element_blank(),
      legend.title     = element_blank(),
      legend.text      = element_text(colour = dublin$muted,
                                      size = base_size - 3),
      plot.title       = element_text(colour = dublin$navy, face = "bold",
                                      hjust = 0, size = base_size - 1)
    )
}

scale_colour_dublin <- function(...) {
  discrete_scale("colour", "dublin",
                 function(n) dublin_series[seq_len(n)], ...)
}
scale_color_dublin <- scale_colour_dublin

scale_fill_dublin <- function(...) {
  discrete_scale("fill", "dublin",
                 function(n) dublin_series[seq_len(n)], ...)
}

scale_fill_dublin_c <- function(...) {
  scale_fill_gradientn(colours = dublin_sequential, ...)
}

scale_fill_dublin_div <- function(...) {
  scale_fill_gradientn(colours = dublin_diverging, ...)
}
