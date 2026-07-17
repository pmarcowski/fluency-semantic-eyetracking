# Match the triad stimuli to Polish lexical/affective norms for the covariate confound test.
#   Affective (valence, arousal, imageability, concreteness): ANPW_R (Imbir 2016), a general
#     4,905-word list read from materials/norms/.
#   Frequency + length: SUBTLEX-PL (Mandera et al. 2015), downloaded on first run.

suppressPackageStartupMessages({ library(tidyverse); library(readxl); library(here) })
here::i_am("scripts/build_norms.R")
norms_dir <- here("data/external/norms")
dir.create(norms_dir, showWarnings = FALSE, recursive = TRUE)

# SUBTLEX-PL (contextual-diversity version): frequency (Zipf) + length. Public supplementary material.
cd3_file <- file.path(norms_dir, "subtlex-pl-cd-3.csv")
if (!file.exists(cd3_file)) {
  zip_file <- file.path(norms_dir, "subtlex_pl.zip")
  download.file("https://static-content.springer.com/esm/art%3A10.3758%2Fs13428-014-0489-4/MediaObjects/13428_2014_489_MOESM1_ESM.zip",
                zip_file, mode = "wb", quiet = TRUE)
  unzip(zip_file, files = "subtlex-pl-cd-3.csv", exdir = norms_dir)
}

stimuli <- read_csv(here("data/processed/stimuli.csv"), show_col_types = FALSE)

# ANPW_R affective norms (means over all raters). Column names carry the dataset's original spellings.
anpw <- read_excel(here("materials/norms/ANPW_R-datasheet-1.xlsx"), sheet = 1) %>%
  transmute(word = str_trim(tolower(`polish word`)),
            valence = as.numeric(Valence_M), arousal = as.numeric(arousal_M),
            imageability = as.numeric(imegability_M), concreteness = as.numeric(concretness_M)) %>%
  filter(!is.na(word)) %>% distinct(word, .keep_all = TRUE)

# SUBTLEX-PL frequency + length.
subtlex <- data.table::fread(cd3_file, select = c("spelling", "zipf.freq", "nchar")) %>%
  as_tibble() %>%
  transmute(word = str_trim(tolower(spelling)), s_freq = zipf.freq, s_length = nchar) %>%
  distinct(word, .keep_all = TRUE)

# One row per (triad, word): affective dims from ANPW_R, frequency/length from SUBTLEX (length falls
# back to the raw character count when a word is absent from SUBTLEX).
words <- stimuli %>%
  pivot_longer(c(word_1, word_2, word_3), values_to = "word") %>%
  mutate(word = str_trim(tolower(word))) %>%
  left_join(anpw, by = "word") %>%
  left_join(subtlex, by = "word") %>%
  mutate(frequency = s_freq,
         length = coalesce(s_length, nchar(word)),
         in_anpw = !is.na(valence),
         freq_matched = !is.na(frequency)) %>%
  select(-s_freq, -s_length, -name)

cat(sprintf("Stimulus words: %d | in ANPW_R: %.0f%% | frequency matched: %.0f%%\n",
            nrow(words), 100 * mean(words$in_anpw), 100 * mean(words$freq_matched)))

# Per-triad properties (mean across the three words; n_anpw = words matched to ANPW_R).
triad_props <- words %>%
  group_by(experiment_id, code, role, affect) %>%
  summarise(across(c(valence, arousal, imageability, concreteness, frequency, length),
                   \(x) mean(x, na.rm = TRUE)),
            n_anpw = sum(in_anpw), .groups = "drop")

dir.create(here("output/tables"), showWarnings = FALSE, recursive = TRUE)
write_csv(triad_props, here("data/processed/stimulus_properties.csv"))
write_csv(words, here("output/tables/stimulus_words_norms.csv"))
cat("Wrote data/processed/stimulus_properties.csv (", nrow(triad_props), "triads)\n")
