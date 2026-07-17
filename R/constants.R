# Constants and analysis parameters for the Dyads-of-Triads fluency eye-tracking study.

# Display (Tobii eye tracker; PsychoPy 'pix' units: origin at screen centre, y pointing up)
screen_width  <- 1920    # px
screen_height <- 1080    # px
sampling_rate <- 60      # Hz
viewing_distance <- 600  # mm (for visual-angle reporting)

# Gaze preprocessing
gaze_margin        <- 0.10  # fraction of half-screen tolerated beyond an edge before a sample is track loss
max_gap_s          <- 0.10  # longest gap (s) bridged by interpolation; longer gaps stay track loss
track_exclude_prop <- 0.40  # max track-loss proportion before a trial/participant is excluded
bin_size           <- 0.5   # s, time bin for the growth-curve analysis (20 bins over the 10 s trial)

# Contrast manipulation (Study 2): black letters (#000000) = high contrast, grey (#e6e6e6) = low;
# conditions are decoded from the stimulus colours by scripts/extract_data.py.

# Smallest effect of interest for power / equivalence (literature-anchored:
# Sweklej et al. 2014; Topolinski & Strack 2009)
sesoi_d <- 0.46

# Factor levels and figure labels
affect_levels   <- c("Negative", "Neutral", "Positive")
contrast_levels <- c("None", "Nonsolvable", "Solvable", "Both")
contrast_labels <- c(
  None        = "No contrast",
  Nonsolvable = "Contrast on nonsolvable",
  Solvable    = "Contrast on solvable",
  Both        = "Contrast on both"
)
