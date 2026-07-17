"""Extract and label iohub eye-tracking (.hdf5) + PsychoPy behavioral (.csv) data for the Dyads-of-Triads fluency study."""

from __future__ import annotations

import argparse
import re
from dataclasses import dataclass
from pathlib import Path

import h5py
import numpy as np
import pandas as pd

ROOT = Path(__file__).resolve().parents[1]
RAW = ROOT / "data" / "raw"
OUT = ROOT / "data" / "processed"


@dataclass(frozen=True)
class Experiment:
    """A study: its iohub session file(s), behavioral-CSV root, and complete-session trial count."""

    name: str
    hdf5: tuple[Path, ...]
    behavioral: Path
    n_trials: int


EXPERIMENTS: dict[str, Experiment] = {
    "exp1": Experiment("exp1", (RAW / "eyetracking" / "exp1.hdf5",),
                       RAW / "behavioral" / "exp1", 15),
    "exp2": Experiment("exp2", (RAW / "eyetracking" / "exp2_cond1.hdf5",
                                RAW / "eyetracking" / "exp2_cond2.hdf5"),
                       RAW / "behavioral" / "exp2", 18),
}

# Solvable-triad valence: Study 1 encodes it in the r-number, Study 2 in the code prefix.
_R_VALENCE = {**{f"r{c:02d}": "Positive" for c in (1, 2, 3, 4, 15)},
              **{f"r{c:02d}": "Negative" for c in (5, 6, 7, 8, 9)},
              **{f"r{c:02d}": "Neutral" for c in (10, 11, 12, 13, 14)}}
_PREFIX_VALENCE = {"poz": "Positive", "neg": "Negative", "neu": "Neutral"}

HIGH_CONTRAST = "#000000"  # black letters = high perceptual contrast; grey (#e6e6e6) = low
NO_RESPONSE = 9            # PsychoPy `acc` sentinel for a trial with no choice within the 10 s window
GAZE_COLS = ["session_id", "time", "left_gaze_x", "left_gaze_y",
             "right_gaze_x", "right_gaze_y", "status"]


# --- iohub .hdf5 -> labelled gaze ---------------------------------------------

def _records(dataset) -> pd.DataFrame:
    """Materialise an h5py structured dataset to a DataFrame, decoding byte-string columns to UTF-8."""
    df = pd.DataFrame.from_records(dataset[:])
    for col in df.columns:
        if df[col].dtype == object and df[col].map(lambda v: isinstance(v, bytes)).any():
            df[col] = df[col].str.decode("utf-8", errors="replace")
    return df


def _read_iohub(path: Path) -> dict[str, pd.DataFrame]:
    """Read gaze samples, message markers, and the session->participant map from one .hdf5 file."""
    with h5py.File(path, "r") as f:
        events = f["data_collection"]["events"]
        gaze = pd.DataFrame.from_records(events["eyetracker"]["BinocularEyeSampleEvent"][:])[GAZE_COLS]
        messages = _records(events["experiment"]["MessageEvent"])[["session_id", "time", "text"]]
        meta = _records(f["data_collection"]["session_meta_data"])[["session_id", "name"]]
    meta["name"] = meta["name"].str.strip()
    return {"gaze": gaze, "messages": messages, "meta": meta}


def _segments(markers: pd.DataFrame, session: int) -> list[tuple[str, float, float]]:
    """Pair `start:<id>`/`end:<id>` markers into ordered (event, t_start, t_end); fail fast on any mismatch."""
    segments: list[tuple[str, float, float]] = []
    open_event: str | None = None
    open_time = 0.0
    for _, row in markers.sort_values("time").iterrows():
        text = str(row["text"])
        if ":" not in text:
            continue
        kind, event = text.split(":", 1)
        event = event.strip()
        if kind == "start":
            if open_event is not None:
                raise ValueError(f"session {session}: '{event}' starts before '{open_event}' ends")
            open_event, open_time = event, float(row["time"])
        elif kind == "end":
            if event != open_event:
                raise ValueError(f"session {session}: end '{event}' has no matching start")
            segments.append((event, open_time, float(row["time"])))
            open_event = None
    if open_event is not None:
        raise ValueError(f"session {session}: start '{open_event}' never ends")
    return segments


def _label_gaze(data: dict[str, pd.DataFrame]) -> pd.DataFrame:
    """Tag each gaze sample with its trial number + event (trial_id); drop validation and between-trial samples."""
    session_to_name = dict(zip(data["meta"]["session_id"], data["meta"]["name"]))
    labelled = []
    for session, g in data["gaze"].groupby("session_id", sort=True):
        if session not in session_to_name:
            raise ValueError(f"session {session} missing from session_meta_data")
        name = str(session_to_name[session]).strip()
        if not name.isdigit():   # skip non-participant sessions (test/debug session names)
            continue
        g = g.copy()
        g["block"], g["trial"], g["event"] = np.nan, np.nan, pd.NA
        markers = data["messages"][data["messages"]["session_id"] == session]
        block, trial = 0, 0
        for event, start, end in _segments(markers, session):
            if event == "validation":   # each calibration starts a new run/block (handles restarts)
                block, trial = block + 1, 0
                continue
            trial += 1
            in_trial = g["time"].between(start, end)
            g.loc[in_trial, ["block", "trial"]] = [max(block, 1), trial]
            g.loc[in_trial, "event"] = event
        g["participant_id"] = name.zfill(3)
        labelled.append(g)
    out = pd.concat(labelled, ignore_index=True).dropna(subset=["trial"])
    out[["block", "trial"]] = out[["block", "trial"]].astype(int)
    cols = ["participant_id", "block", "trial", "event", "time",
            "left_gaze_x", "left_gaze_y", "right_gaze_x", "right_gaze_y", "status"]
    return out[cols]


# --- PsychoPy .csv -> behavioral + stimulus rows ------------------------------

def _bool(series: pd.Series) -> np.ndarray:
    return series.astype(str).str.strip().str.lower().isin({"true", "1", "1.0"}).to_numpy()


def _words(cell) -> list[str]:
    """Parse the three words from a stringified array like \"['a' 'b' 'c']\" (order-canonicalised by sorting)."""
    found = re.findall(r"'([^']*)'", str(cell))
    if len(found) != 3:
        raise ValueError(f"expected 3 words, got {found!r}")
    return sorted(found)


def _valence(code: str) -> str:
    if code[:3] in _PREFIX_VALENCE:
        return _PREFIX_VALENCE[code[:3]]
    if code in _R_VALENCE:
        return _R_VALENCE[code]
    raise ValueError(f"unknown solvable-triad code '{code}'")


def _confidence(cell) -> float:
    """Decision-confidence rating (0-10) from the `ocena_1` textbox, tolerant of stray keystrokes ('q5' -> 5)."""
    match = re.search(r"\d+", str(cell))
    if match is None:
        return np.nan
    value = int(match.group())
    return float(value) if 0 <= value <= 10 else np.nan


def _contrast_side(trials: pd.DataFrame) -> np.ndarray:
    """High-contrast side from the per-trial kolor_l/kolor_p columns (#000000 = high contrast)."""
    def pick(base: str) -> pd.Series:
        # PsychoPy writes the kolor header twice; use the populated (per-trial) copy.
        for col in (c for c in trials.columns if c == base or c.startswith(base + ".")):
            if trials[col].notna().any():
                return trials[col].astype(str).str.strip().str.lower()
        raise ValueError(f"no populated '{base}' column")

    left = pick("kolor_l").eq(HIGH_CONTRAST)
    right = pick("kolor_p").eq(HIGH_CONTRAST)
    return np.select([left & ~right, right & ~left, left & right, ~left & ~right],
                     ["Left", "Right", "Both", "Neither"], default=None)  # "Neither" (not "None": pandas reads that as NaN)


def _read_behavioral(csv: Path, exp: Experiment, condition: str | None
                     ) -> tuple[pd.DataFrame, pd.DataFrame]:
    """Return (per-trial behavioral rows, per-triad stimulus rows) for one participant CSV."""
    raw = pd.read_csv(csv)
    trials = raw[raw["trials.thisN"].notna()].copy()
    if trials.empty:
        raise ValueError(f"{csv.name}: no trial rows")
    # The filename code is the authoritative participant id (matches the iohub session name); the CSV
    # `participant` field is mis-entered in a few sessions (e.g. 057 -> 56, colliding with 056).
    participant = csv.stem.split("_")[0].zfill(3)

    left_solvable = _bool(trials["trl"])
    right_solvable = _bool(trials["trp"])
    left_code, right_code = (trials["trial_id"].astype(str).str.split("_", n=1, expand=True)
                             .to_numpy().T)
    solvable_code = np.where(left_solvable, left_code, right_code)
    nonsolvable_code = np.where(left_solvable, right_code, left_code)
    left_words = trials["tl"].map(_words)
    right_words = trials["tp"].map(_words)
    this_n = trials["trials.thisN"].astype(int).to_numpy()  # PsychoPy trial index, resets to 0 on a restart

    behavioral = pd.DataFrame({
        "experiment_id": exp.name,
        "participant_id": participant,
        "block": np.cumsum(this_n == 0),
        "trial": this_n + 1,
        "event": trials["trial_id"].astype(str).to_numpy(),
        "triad_solvable": solvable_code,
        "affect": [_valence(c) for c in solvable_code],
        "side_solve": np.where(left_solvable, "Left", np.where(right_solvable, "Right", None)),
        # `acc` 9 = no response within the trial window -> missing, not 0/1.
        "accuracy": pd.to_numeric(trials["acc"], errors="coerce").replace(NO_RESPONSE, np.nan).to_numpy(),
        "accuracy_rt": pd.to_numeric(trials["tri_resp.rt"], errors="coerce").to_numpy(),
        "confidence": trials["ocena_1.text"].map(_confidence).to_numpy(),  # 0-10 decision confidence (see _confidence)
        "solution": trials["solution.text"].astype(str).str.strip().replace({"nan": None}).to_numpy(),
        "sex": raw["sex"].dropna().iloc[0] if raw["sex"].notna().any() else None,
        "age": pd.to_numeric(raw["age"], errors="coerce").dropna().iloc[0] if raw["age"].notna().any() else np.nan,
    })
    if exp.name == "exp2":
        behavioral.insert(2, "condition", condition)
        behavioral["side_contrast"] = _contrast_side(trials)

    stimuli = pd.DataFrame([
        {"experiment_id": exp.name, "code": code, "role": role, "affect": affect,
         "word_1": words[0], "word_2": words[1], "word_3": words[2]}
        for code, role, affect, words in (
            [(solvable_code[i], "solvable", behavioral["affect"][i],
              left_words.iloc[i] if left_solvable[i] else right_words.iloc[i]) for i in range(len(trials))]
            + [(nonsolvable_code[i], "nonsolvable", None,
                right_words.iloc[i] if left_solvable[i] else left_words.iloc[i]) for i in range(len(trials))]
        )
    ])
    return behavioral, stimuli


# --- orchestration ------------------------------------------------------------

def _condition_of(hdf5: Path) -> str | None:
    match = re.search(r"_(cond\d+)", hdf5.stem)
    return match.group(1) if match else None


def extract(exp: Experiment) -> dict[str, pd.DataFrame]:
    """Run the full extraction for one experiment, returning gaze, behavioral, and stimulus tables."""
    gaze_parts, behavioral_parts, stimulus_parts = [], [], []
    for hdf5 in exp.hdf5:
        condition = _condition_of(hdf5)
        gaze = _label_gaze(_read_iohub(hdf5))
        if condition:
            gaze.insert(1, "condition", condition)
        gaze_parts.append(gaze)
        behavioral_dir = exp.behavioral / condition if condition else exp.behavioral
        for csv in sorted(behavioral_dir.glob("*.csv")):
            behavioral, stimuli = _read_behavioral(csv, exp, condition)
            behavioral_parts.append(behavioral)
            stimulus_parts.append(stimuli)
    stimuli = (pd.concat(stimulus_parts, ignore_index=True)
               .drop_duplicates(subset=["experiment_id", "code"])
               .sort_values(["experiment_id", "role", "code"], ignore_index=True))
    return {"gaze": pd.concat(gaze_parts, ignore_index=True),
            "behavioral": pd.concat(behavioral_parts, ignore_index=True),
            "stimuli": stimuli}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--exp", choices=[*EXPERIMENTS, "all"], default="all")
    args = parser.parse_args()

    (OUT / "labelled").mkdir(parents=True, exist_ok=True)
    (OUT / "behavioral").mkdir(parents=True, exist_ok=True)
    stimulus_tables = []
    for name in (EXPERIMENTS if args.exp == "all" else [args.exp]):
        result = extract(EXPERIMENTS[name])
        result["gaze"].to_csv(OUT / "labelled" / f"{name}.csv", index=False)
        result["behavioral"].to_csv(OUT / "behavioral" / f"{name}.csv", index=False)
        stimulus_tables.append(result["stimuli"])
        n_gaze = result["gaze"]["participant_id"].nunique()
        n_behavioral = result["behavioral"]["participant_id"].nunique()
        print(f"{name}: gaze {n_gaze} participants / {len(result['gaze']):,} samples; "
              f"behavioral {n_behavioral} participants / {len(result['behavioral'])} trials")

    stimuli = pd.concat(stimulus_tables, ignore_index=True)
    stimuli.to_csv(OUT / "stimuli.csv", index=False)
    print(f"stimuli: {len(stimuli)} unique triads -> {OUT / 'stimuli.csv'}")


if __name__ == "__main__":
    main()
