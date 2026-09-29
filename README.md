# Fluency in semantic coherence detection

Data and code for a two-study eye-tracking investigation of how processing fluency shapes
intuitive semantic-coherence judgments in the **Dyads-of-Triads** task. Study 1 manipulates the emotional
**valence** of the solvable triad (a *semantic* fluency source); Study 2 adds visual **contrast** (a
*perceptual* fluency source). Outcomes: accuracy, response time, confidence, and gaze preference.

Data and analysis code are available on OSF: <https://osf.io/8ks5w>. The raw recordings are deposited separately in the study data repository
(see the paper's Data availability statement); this repository is reproducible from
`data/processed/` onward, or place the raw files under `data/raw/` to re-run extraction.

## Citation

Sweklej, J., Balas, R., Marcowski, P., & Żuk, D. (2026). Fluency in semantic coherence detection:
Insights from response times, confidence, and eye movements. *Consciousness and Cognition*, *145*,
Article 104122. <https://doi.org/10.1016/j.concog.2026.104122>

## Layout

| Path | Contents |
|------|----------|
| `data/processed/` | Extractor + preprocessing outputs (labelled gaze, behavioral, `stimuli.csv`, prepared `.Rds`) |
| `materials/` | PsychoPy experiments, stimuli, and ANPW_R affective norms (Imbir 2016) |
| `scripts/` | `extract_data.py` (HDF5 + CSV → labelled data) and standalone R analyses |
| `R/` | Sourced helpers: `constants`, `aoi_definitions`, `utils`, `theme`, `reporting` |
| `analysis/` | Quarto notebooks: preprocessing, per-study analyses, robustness |
| `output/` | Figures and result tables, per study (generated at render; archived on OSF) |
| `docs/` | Rendered analysis website (findings, per-study notebooks, data dictionary) |

## Reproduce

**Python** (extractor): conda env with `requirements.txt` (`h5py`, `pandas`, `numpy`).
**R** 4.5 with the packages listed in each notebook's setup chunk (`tidyverse`, `eyetrackingR`, `glmmTMB`,
`emmeans`, `car`, `performance`, `rmcorr`, `patchwork`, `see`, …), plus `readxl` and `data.table` for the
norming script and `lme4`/`simr` for the power script.

From the project root:

```sh
# 1. Build labelled gaze + behavioral + stimulus tables from the raw .hdf5/.csv
python scripts/extract_data.py            # writes data/processed/

# 2. Stimulus norming (SUBTLEX-PL downloaded; ANPW_R read from materials/norms/) and power
Rscript scripts/build_norms.R             # writes data/processed/stimulus_properties.csv + output/tables/
Rscript scripts/power_simulation.R        # writes output/power/

# 3. Preprocess and analyse; renders the analysis website to docs/ (requires the step-1/2 outputs)
quarto render analysis
```

The analysis notebooks set `set.seed(42)`; the pipeline is deterministic. See the **Data & pipeline** page
(`docs/data-pipeline.html`) for the data contract and column dictionary.

## Licensing

Code is released under the [MIT License](LICENSE). The ANPW_R affective norms redistributed in
`materials/norms/` are © Imbir (2016), published under the Creative Commons Attribution (CC-BY)
license — see `materials/norms/SOURCE.md` for provenance.
