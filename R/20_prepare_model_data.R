# Build the model-ready dataset and the evaluation splits shared by every model.
# Decisions (2026-11-13, see spec.md "Revisions after data checks"):
#   - window Sep 2010 -> latest month with Y and X1, for ALL models
#   - tax-exclusive logs; shortage dummy from Aug 2024; no 2007/2012 dummies
#   - holdout = last 12 months (first 3 = short-horizon holdout)
#   - rolling origins: 96-month training window, step 1, h = 3 and 12, regime split at Aug 2024
# Output: data/processed/model_data.csv, data/processed/splits.rds
suppressPackageStartupMessages(library(dplyr))
dir.create("data/processed", showWarnings = FALSE)

START <- as.Date("2010-09-01"); BREAK <- as.Date("2024-08-01"); TAX_CHANGE <- as.Date("2014-04-01")
TRAIN_WIN <- 96L; HORIZONS <- c(3L, 12L); HOLDOUT <- 12L

m <- read.csv("data/interim/monthly.csv") |> mutate(date = as.Date(date))
rel <- read.csv("data/interim/x1_monthly_releases.csv") |> mutate(date = as.Date(date))

# thin-month flag: release volume below half the median volume for that calendar month in other years
rel <- rel |> mutate(mon = format(date, "%m")) |> group_by(mon) |>
  mutate(med_other = sapply(seq_along(volume_t), function(i) median(volume_t[-i], na.rm = TRUE))) |> ungroup() |>
  mutate(x1_thin = !is.na(med_other) & volume_t < 0.5 * med_other)

end_date <- max(m$date[!is.na(m$y) & !is.na(m$x1)])
d <- m |> filter(date >= START, date <= end_date) |>
  left_join(rel |> select(date, x1_volume_t = volume_t, x1_thin), by = "date") |>
  mutate(tax = ifelse(date < TAX_CHANGE, 1.05, 1.08),
         y_ex = y / tax, x1_ex = x1 / tax,
         ly = log(y_ex), lx1 = log(x1_ex), lx2 = log(x2_all), lx2_energy = log(x2_energy),
         x3_temp = x3, x3b_precip = x3b, lx4 = log(x4),
         shortage = as.integer(date >= BREAK), sep = as.integer(format(date, "%m") == "09"),
         x1_thin = coalesce(x1_thin, FALSE),
         x1_prelim = date == end_date) |>   # latest MAFF month is a 速報 and gets revised
  select(date, y, x1, tax, y_ex, x1_ex, ly, lx1, lx2, lx2_energy, x3_temp, x3b_precip, lx4,
         shortage, sep, x1_thin, x1_prelim, x1_volume_t, x1_src)

# ---- assertions ----
core <- c("ly", "lx1", "lx2", "x3_temp", "x3b_precip")
stopifnot(min(d$date) == START, !anyDuplicated(d$date),
          all(diff(as.numeric(format(d$date, "%Y")) * 12 + as.numeric(format(d$date, "%m"))) == 1),
          !anyNA(d[core]))
write.csv(d, "data/processed/model_data.csv", row.names = FALSE)

# ---- splits (indices into model_data rows) ----
N <- nrow(d)
holdout <- list(long = (N - HOLDOUT + 1):N, short = (N - HOLDOUT + 1):(N - HOLDOUT + 3))
origins <- do.call(rbind, lapply(HORIZONS, function(h) {
  o <- TRAIN_WIN:(N - h)
  data.frame(h = h, origin = o, origin_date = d$date[o],
             train_start = o - TRAIN_WIN + 1L, train_end = o, test_end = o + h,
             regime = ifelse(d$date[o] < BREAK, "pre", "post"),
             # usable for ensemble weights only if the whole forecast window is before the holdout
             pre_holdout = (o + h) < min(holdout$long))
}))
splits <- list(start = START, end = end_date, n = N, break_date = BREAK, train_window = TRAIN_WIN,
               holdout = holdout, holdout_dates = lapply(holdout, function(i) range(d$date[i])),
               rolling = origins, prebreak_fit = which(d$date < BREAK))
saveRDS(splits, "data/processed/splits.rds")

cat(sprintf("model_data: %d months, %s to %s; no NA in %s\n", N, format(START, "%b %Y"),
            format(end_date, "%b %Y"), paste(core, collapse = ", ")))
cat(sprintf("holdout long: %s - %s | short: %s - %s\n", format(d$date[min(holdout$long)], "%b %Y"),
            format(d$date[N], "%b %Y"), format(d$date[min(holdout$short)], "%b %Y"), format(d$date[max(holdout$short)], "%b %Y")))
cat(sprintf("pre-break sensitivity fit: %d months (to %s)\n", length(splits$prebreak_fit),
            format(d$date[max(splits$prebreak_fit)], "%b %Y")))
cat("rolling origins (96-month window):\n")
print(origins |> group_by(h, regime) |> summarise(origins = n(), usable_for_weights = sum(pre_holdout), .groups = "drop") |> as.data.frame())
cat("thin/preliminary X1 months:", paste(format(d$date[d$x1_thin | d$x1_prelim], "%Y-%m"), collapse = ", "), "\n")
