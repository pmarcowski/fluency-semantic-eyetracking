# Statistical-reporting helpers for the fluency eye-tracking notebooks.

#' Significance stars from a p-value (`***` < .001, `**` < .01, `*` < .05, else `ns`).
sig_stars <- function(p) {
  cut(p, c(-Inf, .001, .01, .05, Inf), labels = c("***", "**", "*", "ns"))
}

#' Coerce an `emmeans` grid/summary to a data frame with consistent CI column names.
#'
#' Asymptotic (z-based) fits — e.g. Gaussian `glmmTMB` — label confidence limits `asymp.LCL`/`asymp.UCL`;
#' this renames them to `lower.CL`/`upper.CL` so downstream code can use one set of names.
emm_df <- function(x) {
  df <- as.data.frame(x)
  if ("asymp.LCL" %in% names(df)) df <- dplyr::rename(df, lower.CL = asymp.LCL, upper.CL = asymp.UCL)
  df
}
