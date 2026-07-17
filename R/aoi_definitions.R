# Areas of Interest for the two side-by-side triads (screen pixels, origin top-left).
# Each box is 400 x 300 px over a triad; the solvable/nonsolvable boxes swap with the
# solvable side (the `Trial` column matches the per-trial Target = side of the solvable triad).

aoi_box_solvable <- data.frame(
  Trial  = c("Left", "Right"),
  Left   = c(310, 1210),
  Top    = c(390, 390),
  Right  = c(710, 1610),
  Bottom = c(690, 690)
)

aoi_box_nonsolvable <- data.frame(
  Trial  = c("Left", "Right"),
  Left   = c(1210, 310),
  Top    = c(390, 390),
  Right  = c(1610, 710),
  Bottom = c(690, 690)
)
