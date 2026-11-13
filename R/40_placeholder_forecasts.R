# PLACEHOLDER forecasts, for laying out the dashboard's forecast section.
# These are quick stand-ins, NOT the project's final models (see spec.md "Modelling plan"):
#   - Random walk: last tax-exclusive price carried forward (benchmark)
#   - ARIMA:       forecast::auto.arima on log tax-exclusive retail, shortage dummy as xreg
#   - VAR:         vars::VAR on Δlog retail and Δlog wholesale, lag by SC (max 6), shortage dummy exogenous
#   - Ensemble:    equal-weight average of ARIMA and VAR (in logs)
# Limits for VAR are cumulated from per-step standard errors (assumes independent steps) and the ensemble
# averages its members' limits; both are crude and will be replaced.
# Output: data/processed/forecasts_placeholder.json (read by R/30_export_dashboard.R)
suppressPackageStartupMessages({ library(dplyr); library(forecast); library(vars); library(jsonlite) })

md <- read.csv("data/processed/model_data.csv") |> mutate(date = as.Date(date))
sp <- readRDS("data/processed/splits.rds")
H <- 12L; Z <- qnorm(0.975)

fit_all <- function(d, h = H) {
  ly <- d$ly; n <- nrow(d)
  out <- list()
  # random walk
  sd_rw <- sd(diff(ly))
  out$`Random walk` <- data.frame(mean = rep(ly[n], h), lo = ly[n] - Z * sd_rw * sqrt(1:h), hi = ly[n] + Z * sd_rw * sqrt(1:h))
  # ARIMA with shortage dummy
  fa <- auto.arima(ly, xreg = d$shortage, seasonal = FALSE)
  fc <- forecast(fa, h = h, xreg = rep(1, h), level = 95)
  out$ARIMA <- data.frame(mean = as.numeric(fc$mean), lo = as.numeric(fc$lower), hi = as.numeric(fc$upper))
  attr(out$ARIMA, "spec") <- paste0("ARIMA(", paste(arimaorder(fa), collapse = ","), ") + shortage dummy")
  # VAR in differences
  dd <- data.frame(dly = diff(ly), dlx1 = diff(d$lx1))
  ex <- matrix(d$shortage[-1], dimnames = list(NULL, "shortage"))
  p <- VARselect(dd, lag.max = 6, type = "const", exogen = ex)$selection[["SC(n)"]]
  fv <- do.call(VAR, list(y = dd, p = p, type = "const", exogen = ex))  # embeds ex in the call; predict() re-evaluates it
  pv <- predict(fv, n.ahead = h, ci = 0.95, dumvar = matrix(1, h, 1, dimnames = list(NULL, "shortage")))$fcst$dly
  se <- (pv[, "upper"] - pv[, "fcst"]) / Z
  m <- ly[n] + cumsum(pv[, "fcst"]); s <- sqrt(cumsum(se^2))
  out$VAR <- data.frame(mean = m, lo = m - Z * s, hi = m + Z * s)
  attr(out$VAR, "spec") <- sprintf("VAR(%d) on Δlog retail, Δlog wholesale + shortage dummy", p)
  # ensemble
  out$Ensemble <- data.frame(mean = (out$ARIMA$mean + out$VAR$mean) / 2,
                             lo = (out$ARIMA$lo + out$VAR$lo) / 2, hi = (out$ARIMA$hi + out$VAR$hi) / 2)
  out
}

# ---- holdout: fit through the month before the holdout, forecast the 12 holdout months ----
ho <- sp$holdout$long
train <- md[seq_len(min(ho) - 1), ]
fh <- fit_all(train, length(ho))
actual <- md$y_ex[ho]
ase <- lapply(fh, function(f) { e <- exp(f$mean) - actual
  list(h3 = round(mean(e[1:3]^2)), h12 = round(mean(e^2)), roll_h3 = NULL, roll_h12 = NULL) })

# ---- final: refit on all data, forecast 12 months ahead ----
ff <- fit_all(md)
last <- max(md$date)
fdates <- seq(last, by = "month", length.out = H + 1)[-1]
tax_now <- 1.08
tax_cut <- ifelse(fdates >= as.Date("2027-04-01"), 1.01, 1.08)   # food tax cut to 1% from Apr 2027 (if passed)
models <- lapply(names(ff), function(nm) {
  f <- ff[[nm]]
  path <- data.frame(date = format(fdates, "%Y-%m"),
                     mean_ex = round(exp(f$mean)), lo95_ex = round(exp(f$lo)), hi95_ex = round(exp(f$hi)))
  list(model = nm, spec = attr(f, "spec") %||% if (nm == "Random walk") "Last price carried forward" else "Average of ARIMA and VAR (log scale)",
       path = path, ase = ase[[nm]],
       holdout_path = data.frame(date = format(md$date[ho], "%Y-%m"), mean_ex = round(exp(fh[[nm]]$mean))))
})

out <- list(
  status = "placeholder",
  note = "Placeholder models for layout only. Not the project's final models and not advice.",
  origin = format(last, "%Y-%m"), horizon = H,
  holdout = list(start = format(md$date[min(ho)], "%Y-%m"), end = format(md$date[max(ho)], "%Y-%m"),
                 actual_ex = round(actual)),
  tax = list(dates = format(fdates, "%Y-%m"), no_cut = rep(tax_now, H), cut = tax_cut,
             note = "Prices modelled without tax; tax added back: 8% throughout, or 1% from Apr 2027 if the food tax cut passes"),
  models = models)
dir.create("data/processed", showWarnings = FALSE)
write_json(out, "data/processed/forecasts_placeholder.json", auto_unbox = TRUE, digits = NA, null = "null", pretty = TRUE)

for (m in models) cat(sprintf("%-12s %-55s Sep 2027 ¥%s ex-tax [%s, %s] | holdout ASE h3 %s, h12 %s\n", m$model, m$spec,
                              format(tail(m$path$mean_ex, 1), big.mark = ","), format(tail(m$path$lo95_ex, 1), big.mark = ","),
                              format(tail(m$path$hi95_ex, 1), big.mark = ","), format(m$ase$h3, big.mark = ","), format(m$ase$h12, big.mark = ",")))
