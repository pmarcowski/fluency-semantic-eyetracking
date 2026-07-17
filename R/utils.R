# Data-processing utilities for the Dyads-of-Triads fluency eye-tracking study.

library(dplyr)
library(tibble)

#' Join labelled gaze with per-trial behavioral data.
#'
#' Keeps each participant's last run (`block`) to handle restarts, caps to the first
#' `n_trials` trials, and inner-joins on the shared trial keys so that only gaze and
#' behavioral records describing the same stimulus survive.
#'
#' @param gaze,behavioral Tibbles from the extractor (`participant_id`, `block`, `trial`,
#'   `event`, optionally `condition`).
#' @param n_trials Trials in a complete session.
#' @return One row per retained gaze sample with the behavioral fields attached.
combine_gaze_behavioral <- function(gaze, behavioral, n_trials) {
  last_block <- function(df) {
    df %>%
      group_by(participant_id) %>%
      filter(block == max(block), trial <= n_trials) %>%
      ungroup() %>%
      select(-block)
  }
  keys <- intersect(c("participant_id", "condition", "trial", "event"), names(gaze))
  inner_join(last_block(gaze), last_block(behavioral), by = keys)
}

#' Best-available-eye gaze in screen pixels, with a track-loss flag.
#'
#' Averages the two eyes when both are valid, falls back to the single valid eye, and
#' flags track loss when neither is. An eye is valid when its coordinates are present and
#' fall within the screen bounds expanded by `margin`. Input is PsychoPy centred pixels
#' (origin centre, y up); output is screen pixels (origin top-left, y down).
#'
#' @return A tibble with `gaze_x`, `gaze_y`, and `trackloss`.
compute_binocular_gaze <- function(left_x, left_y, right_x, right_y,
                                   screen_width, screen_height, margin = 0.1) {
  bound_x <- screen_width / 2 * (1 + margin)
  bound_y <- screen_height / 2 * (1 + margin)
  valid <- function(x, y) !is.na(x) & !is.na(y) & abs(x) <= bound_x & abs(y) <= bound_y
  lv <- valid(left_x, left_y)
  rv <- valid(right_x, right_y)
  cx <- case_when(lv & rv ~ (left_x + right_x) / 2, lv ~ left_x, rv ~ right_x, TRUE ~ NA_real_)
  cy <- case_when(lv & rv ~ (left_y + right_y) / 2, lv ~ left_y, rv ~ right_y, TRUE ~ NA_real_)
  tibble(
    gaze_x    = cx + screen_width / 2,
    gaze_y    = screen_height / 2 - cy,
    trackloss = is.na(cx)
  )
}

#' Linear interpolation of a gaze coordinate within a trial, capping the gap length.
#'
#' Interpolates missing values across gaps no longer than `max_gap` (in the units of
#' `time`); longer gaps are left as `NA` (track loss). Assumes the data are ordered and
#' already grouped by participant and trial.
interpolate_coordinate <- function(coord, time, max_gap) {
  ok <- !is.na(coord)
  if (sum(ok) < 2) return(coord)
  filled <- approx(time[ok], coord[ok], xout = time, rule = 1)$y
  valid_time <- time[ok]
  for (i in which(!ok)) {
    before <- valid_time[valid_time < time[i]]
    after <- valid_time[valid_time > time[i]]
    if (length(before) == 0L || length(after) == 0L || (min(after) - max(before)) > max_gap) {
      filled[i] <- NA
    }
  }
  filled
}

#' Flag reaction-time outliers per participant using the 1.5 * IQR rule.
#'
#' Operates on trial-level RTs that may be repeated across the gaze samples of a trial.
#'
#' @return A logical vector (one element per input row) marking samples from outlier trials.
identify_rt_outliers <- function(rt, trial, iqr_multiplier = 1.5) {
  unique_data <- tibble(rt = rt, trial = trial) %>% distinct(trial, rt)
  valid_rts <- unique_data$rt[!is.na(unique_data$rt)]
  q1 <- quantile(valid_rts, 0.25)
  q3 <- quantile(valid_rts, 0.75)
  iqr <- q3 - q1
  lower <- q1 - iqr_multiplier * iqr
  upper <- q3 + iqr_multiplier * iqr
  is_outlier <- if_else(is.na(unique_data$rt), FALSE, unique_data$rt < lower | unique_data$rt > upper)
  lookup <- tibble(trial = unique_data$trial, is_outlier = is_outlier)
  left_join(tibble(trial = trial), lookup, by = "trial")$is_outlier
}

#' Flag gaze-coordinate outliers within a trial.
#'
#' Uses Mahalanobis distance (chi-square cut-off at `threshold`); additionally flags the
#' whole trial when a high proportion (`constant_threshold`) of coordinates are identical
#' (a stuck-signal signature).
#'
#' @return A logical vector marking outlier samples.
identify_gaze_outliers <- function(x, y, threshold = 0.975, constant_threshold = 0.95) {
  valid <- !is.na(x) & !is.na(y)
  x_valid <- x[valid]
  y_valid <- y[valid]
  result <- rep(FALSE, length(x))
  if (length(x_valid) < 3) return(result)

  x_mode_prop <- max(table(x_valid)) / length(x_valid)
  y_mode_prop <- max(table(y_valid)) / length(y_valid)
  if (x_mode_prop >= constant_threshold || y_mode_prop >= constant_threshold) {
    result[valid] <- TRUE
    return(result)
  }

  center <- c(mean(x_valid), mean(y_valid))
  # A degenerate (collinear / near-constant) spread gives a singular covariance; such a trial
  # has no meaningful Mahalanobis distance, so flag no outliers. rcond() mirrors solve()'s own
  # computational-singularity criterion; any other error propagates.
  cov_mat <- cov(cbind(x_valid, y_valid))
  if (!all(is.finite(cov_mat)) || rcond(cov_mat) < .Machine$double.eps) return(result)
  distances <- mahalanobis(cbind(x_valid, y_valid), center, cov_mat)
  result[valid] <- distances > qchisq(threshold, df = 2)
  result
}
