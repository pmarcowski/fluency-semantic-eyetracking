# ggplot theme and inline-reporting formatters for the fluency eye-tracking notebooks.

library(ggplot2)

theme_set(
  see::theme_modern(base_size = 12) +
    theme(
      plot.title      = element_text(face = "bold", hjust = 0.5),
      plot.subtitle   = element_text(colour = "grey40", hjust = 0.5),
      legend.position = "bottom"
    )
)

# Shared affect palette (Negative / Neutral / Positive)
affect_colours <- c(Negative = "#C44E52", Neutral = "#8C8C8C", Positive = "#55A868")

# Inline-reporting formatters, for `r ...` calls in prose
fmt_p   <- function(p) ifelse(p < .001, "< .001", paste0("= ", formatC(p, format = "f", digits = 3)))
fmt_n   <- function(x, digits = 2) formatC(x, format = "f", digits = digits)
fmt_chi <- function(stat, df, p) sprintf("χ²(%d) = %s, p %s", df, fmt_n(stat), fmt_p(p))
