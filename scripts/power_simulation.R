# Simulation-based power for the GLMM effects (H2-H4) at the smallest effect of interest, d = 0.46.
# Power to detect a SESOI-sized affect (Study 1) / contrast (Study 2) effect on RT, confidence, and gaze.
# Models are fitted with lme4 (not glmmTMB) because simr::powerSim requires merMod fits.

suppressPackageStartupMessages({ library(tidyverse); library(lme4); library(simr); library(here) })
here::i_am("scripts/power_simulation.R")
set.seed(42)
SESOI_D <- 0.46
NSIM <- 200
out <- here("output/power"); dir.create(out, showWarnings = FALSE, recursive = TRUE)

# Trial-level outcomes: log-RT, confidence, gaze preference (collapsed over time).
trial_data <- function(e, extra = character()) e %>%
  group_by(across(all_of(c("participant_id", "affect", extra, "trial")))) %>%
  summarise(log_rt = log(first(accuracy_rt)), confidence = first(confidence),
            solv = sum(Solvable, na.rm = TRUE), nonsolv = sum(Nonsolvable, na.rm = TRUE), .groups = "drop") %>%
  mutate(preference = (solv - nonsolv) / (solv + nonsolv))

# Set one representative coefficient to a SESOI-sized raw effect, then simulate its power (Wald t-test).
# The model is fitted at the call site; a by-participant random intercept is used.
sim_power <- function(m, coef, label) {
  if (!coef %in% names(fixef(m))) {
    stop(label, ": coefficient '", coef, "' not found in the fitted model.", call. = FALSE)
  }
  fixef(m)[coef] <- SESOI_D * sigma(m)
  s <- summary(powerSim(m, test = fixed(coef, "t"), nsim = NSIM, progress = FALSE))
  cat(sprintf("%-36s power = %.1f%% [%.1f, %.1f]\n", label, 100 * s$mean, 100 * s$lower, 100 * s$upper))
  tibble(analysis = label, power = s$mean, lower = s$lower, upper = s$upper, nsim = NSIM)
}

d1 <- trial_data(readRDS(here("data/processed/prepared/exp1.Rds")))
d2 <- trial_data(readRDS(here("data/processed/prepared/exp2.Rds")), "contrast")
fin <- function(d, v) d %>% filter(is.finite(.data[[v]]))

res <- bind_rows(
  sim_power(lmer(log_rt ~ affect + (1 | participant_id), fin(d1, "log_rt")), "affectPositive", "Study 1 affect -> RT"),
  sim_power(lmer(confidence ~ affect + (1 | participant_id), fin(d1, "confidence")), "affectPositive", "Study 1 affect -> confidence"),
  sim_power(lmer(preference ~ affect + (1 | participant_id), fin(d1, "preference")), "affectPositive", "Study 1 affect -> gaze"),
  sim_power(lmer(log_rt ~ affect * contrast + (1 | participant_id), fin(d2, "log_rt")), "contrastBoth", "Study 2 contrast -> RT"),
  sim_power(lmer(confidence ~ affect * contrast + (1 | participant_id), fin(d2, "confidence")), "contrastBoth", "Study 2 contrast -> confidence"),
  sim_power(lmer(preference ~ affect * contrast + (1 | participant_id), fin(d2, "preference")), "contrastBoth", "Study 2 contrast -> gaze")
)
write_csv(res, file.path(out, "power_results.csv"))
cat("done\n")
