# Export everything the dashboard needs to docs/data.json.
# All "% change" values here are simple percent changes (100 * (a/b - 1)), never log differences.
# Reads: data/processed/model_data.csv, data/interim/{monthly,x1_monthly_releases,x3_niigata_august,
#        x3b_niigata_jja_precip}.csv
suppressPackageStartupMessages({ library(dplyr); library(jsonlite) })
dir.create("docs", showWarnings = FALSE)

pct <- function(a, b) 100 * (a / b - 1)
BREAK <- as.Date("2024-08-01"); START <- as.Date("2010-09-01")

md  <- read.csv("data/processed/model_data.csv") |> mutate(date = as.Date(date))
mon <- read.csv("data/interim/monthly.csv")      |> mutate(date = as.Date(date))
rel <- read.csv("data/interim/x1_monthly_releases.csv") |> mutate(date = as.Date(date))
t3  <- read.csv("data/interim/x3_niigata_august.csv")
p3  <- read.csv("data/interim/x3b_niigata_jja_precip.csv")
last <- max(md$date)

# ---- monthly series (window) ----
yoy <- mon |> arrange(date) |>
  mutate(prev = as.Date(sapply(date, function(d) seq(d, by = "-1 year", length.out = 2)[2]), origin = "1970-01-01")) |>
  left_join(mon |> select(prev = date, y_prev = y, x2_prev = x2_all), by = "prev") |>
  transmute(date, yoy_y = pct(y, y_prev), yoy_x2 = pct(x2_all, x2_prev))
base <- md |> filter(date >= START, date < START + 365) |> summarise(y = mean(y_ex), x1 = mean(x1_ex))
monthly <- md |> left_join(yoy, by = "date") |>
  mutate(markup = (y_ex / 5) / (x1_ex / 54),              # retail ¥/kg ÷ wholesale ¥/kg milled (0.9 yield)
         idx_y = 100 * y_ex / base$y, idx_x1 = 100 * x1_ex / base$x1, x4 = exp(lx4)) |>
  transmute(date = format(date, "%Y-%m"), y, y_ex = round(y_ex, 1), x1, x1_ex = round(x1_ex, 1),
            idx_y = round(idx_y, 2), idx_x1 = round(idx_x1, 2), markup = round(markup, 3),
            yoy_y = round(yoy_y, 1), yoy_x2 = round(yoy_x2, 1), x2 = round(exp(lx2), 1), x4 = round(x4),
            shortage, x1_thin, x1_prelim, x1_volume_t)

pre <- md |> filter(date < BREAK) |> mutate(m = (y_ex / 5) / (x1_ex / 54))
markup_pre_mean <- mean(pre$m)

# ---- crop-year weather ----
crop_years <- t3 |> filter(year >= 2010) |> select(year, aug_temp, aug_anom) |>
  inner_join(p3 |> select(year, jja_mm, jja_pct), by = "year") |>
  mutate(across(c(aug_anom, jja_pct), ~ round(.x, 2)))
aug23_rain <- 2.0   # from data/raw/jma/niigata_monthly_s1_2023.html, August precipitation total (mm)

# ---- cross-correlations (same definition as sanity_checks.Rmd §7.2) ----
dl <- function(x) c(NA, diff(log(x)))
cc <- md |> mutate(dy = dl(y_ex), dx1 = dl(x1_ex)) |> filter(!is.na(dy))
ccf_df <- function(d, period) { k <- ccf(d$dx1, d$dy, lag.max = 6, plot = FALSE, na.action = na.pass)
  data.frame(period = period, lag = -k$lag[, 1, 1], r = round(k$acf[, 1, 1], 3), band = round(2 / sqrt(nrow(d)), 3)) |> arrange(lag) }
ccf_all <- rbind(ccf_df(cc |> filter(date < BREAK), "pre"), ccf_df(cc, "all"))

# ---- tiles ----
g <- function(d, col) md[[col]][md$date == d]
peak_i <- which.max(md$y)
prev_m <- seq(last, by = "-1 month", length.out = 2)[2]; prev_y <- seq(last, by = "-1 year", length.out = 2)[2]
cy <- crop_years |> filter(year == as.integer(format(last, "%Y")) - (as.integer(format(last, "%m")) < 9))
tiles <- list(
  retail = list(value = g(last, "y"), unit = "¥ per 5 kg", yoy_pct = round(pct(g(last, "y"), g(prev_y, "y")), 1),
                from_peak_pct = round(pct(g(last, "y"), md$y[peak_i]), 1), peak = md$y[peak_i], peak_date = format(md$date[peak_i], "%Y-%m")),
  wholesale = list(value = g(last, "x1"), unit = "¥ per 60 kg brown rice", mom_pct = round(pct(g(last, "x1"), g(prev_m, "x1")), 1),
                   volume_t = g(last, "x1_volume_t"), thin = isTRUE(g(last, "x1_thin")), prelim = isTRUE(g(last, "x1_prelim"))),
  markup = list(value = round((g(last, "y_ex") / 5) / (g(last, "x1_ex") / 54), 2), pre_mean = round(markup_pre_mean, 2),
                pre_min = round(min(pre$m), 2), pre_max = round(max(pre$m), 2)),
  weather = list(crop_year = cy$year, aug_anom = round(cy$aug_anom, 1), jja_pct = round(cy$jja_pct)))

# ---- events (policy dates verified 2026-11-13) ----
x1_pct <- function(d) round(pct(g(as.Date(d), "x1"), g(seq(as.Date(d), by = "-1 month", length.out = 2)[2], "x1")))
events <- list(
  list(date = "2024-08", label = "Megaquake advisory", detail = "JMA's first Nankai Trough advisory (8 Aug 2024) set off panic buying; some stores rationed rice.",
       source = "https://thestar.com.my/aseanplus/aseanplus-news/2024/08/10/japanese-urged-to-avoid-panic-buying-as-megaquake-fears-spread"),
  list(date = "2024-09", label = sprintf("2024 crop +%d%%", x1_pct("2024-09-01")), detail = "New-crop wholesale price jumps on thin inventories.", source = "MAFF"),
  list(date = "2025-03", label = "Stockpile auctions", detail = "First government stockpile auction, 10 Mar 2025 (150,000 t offered).",
       source = "https://abs-cbn.com/news/business/2025/3/10/japan-auctions-emergency-rice-reserves-as-prices-soar-1231"),
  list(date = "2025-09", label = sprintf("2025 crop +%d%%", x1_pct("2025-09-01")), detail = "New-crop wholesale price reprices higher again.", source = "MAFF"),
  list(date = format(last, "%Y-%m"), label = sprintf("2026 crop %d%%", x1_pct(format(last, "%Y-%m-01"))),
       detail = "New-crop wholesale price falls sharply. Preliminary and thin volume.", source = "MAFF"))

# ---- coverage & flags ----
series <- c(y = "Retail (Y)", x1 = "Wholesale (X1)", x2_all = "Import prices (X2)", x3 = "Aug temperature (X3)",
            x3b = "Jun–Aug rain (X3b)", x4 = "Visitors (X4)")
coverage <- lapply(names(series), function(s) { d <- mon$date[!is.na(mon[[s]])]
  list(series = series[[s]], first = format(min(d), "%Y-%m"), last = format(max(d), "%Y-%m"), months = length(d),
       spans = { r <- rle(diff(as.numeric(format(d, "%Y")) * 12 + as.numeric(format(d, "%m"))) == 1)
                 ends <- cumsum(r$lengths); starts <- c(1, head(ends, -1) + 1)
                 lapply(which(r$values), function(i) c(format(d[starts[i]], "%Y-%m"), format(d[ends[i] + 1], "%Y-%m"))) }) })
flags <- list(
  list(level = "warning", text = sprintf("Latest wholesale month (%s) is preliminary (速報) and thin: %s t traded.", format(last, "%b %Y"),
                                          format(g(last, "x1_volume_t"), big.mark = ","))),
  list(level = "warning", text = sprintf("Low-volume wholesale months: %s.", paste(format(md$date[md$x1_thin], "%b %Y"), collapse = ", "))),
  list(level = "info", text = "Wholesale monthly data starts Sep 2010 (missing 2009 crop); all models use Sep 2010 onward."),
  list(level = "info", text = "e-Stat retail prices before Jan 2002 are per 10 kg (outside the window)."),
  list(level = "info", text = "Tax: prices shown with tax are as published; 'without tax' divides by 1.05 before Apr 2014 and 1.08 after."))

sources <- list(
  list(series = "Retail price (Y)", source = "Statistics Bureau, Retail Price Survey via e-Stat (table 0003421913, item 1001, Tokyo ku-area)", url = "https://www.e-stat.go.jp/"),
  list(series = "Wholesale price (X1)", source = "MAFF, rice relative trading prices (相対取引価格), all-brand average", url = "https://www.maff.go.jp/j/seisan/keikaku/soukatu/aitaikakaku.html"),
  list(series = "Import prices (X2)", source = "Bank of Japan, Import Price Index, yen basis (PRCG20_2600000000)", url = "https://www.stat-search.boj.or.jp/"),
  list(series = "Weather (X3, X3b)", source = "JMA past weather data, Niigata (47604)", url = "https://www.data.jma.go.jp/stats/etrn/index.php"),
  list(series = "Visitors (X4)", source = "JNTO visitor arrivals", url = "https://www.jnto.go.jp/statistics/data/visitors-statistics/"))

# ---- forecast placeholder: format the modelling scripts will fill ----
forecast_schema <- list(
  status = "pending",
  note = "Filled by the modelling scripts. One entry per model; tax scenarios applied from Apr 2027.",
  example = list(model = "Ensemble", origin = format(last, "%Y-%m"),
                 path = list(list(date = "2026-10", mean = 0, lo95 = 0, hi95 = 0)),
                 tax_scenarios = list(cut = "1% food tax from Apr 2027", no_cut = "8% throughout"),
                 ase = list(h3 = NULL, h12 = NULL, roll_h3 = NULL, roll_h12 = NULL)))

out <- list(
  meta = list(title = "Tokyo Rice Prices", as_of = format(last, "%Y-%m"), built = format(Sys.Date()),
              window_start = format(START, "%Y-%m"), break_date = format(BREAK, "%Y-%m"),
              aug23_rain_mm = aug23_rain, markup_def = "Retail ¥/kg ÷ wholesale ¥/kg (60 kg brown rice → 54 kg milled)"),
  tiles = tiles, monthly = monthly, crop_years = crop_years, ccf = ccf_all, events = events,
  coverage = coverage, flags = flags, sources = sources, forecast = NULL, forecast_schema = forecast_schema)
write_json(out, "docs/data.json", auto_unbox = TRUE, null = "null", na = "null", digits = NA, pretty = FALSE)
cat(sprintf("docs/data.json: %d months, as of %s | retail ¥%s (%+.1f%% yoy, %+.1f%% from peak) | wholesale ¥%s (%+.1f%% m/m) | markup %.2f (pre mean %.2f) | summer %d: %+.1f °C, %d%% rain\n",
            nrow(monthly), format(last, "%Y-%m"), format(tiles$retail$value, big.mark = ","), tiles$retail$yoy_pct, tiles$retail$from_peak_pct,
            format(tiles$wholesale$value, big.mark = ","), tiles$wholesale$mom_pct, tiles$markup$value, tiles$markup$pre_mean,
            tiles$weather$crop_year, tiles$weather$aug_anom, tiles$weather$jja_pct))
