# Parse raw files in data/raw/ into tidy monthly series and join them.
# Output: data/interim/monthly.csv (one row per month, tax-INCLUSIVE, no transforms)
#         data/interim/x1_monthly_releases.csv (MAFF monthly releases incl. volume)
#         data/interim/x1_annual_crop_avg.csv  (crop-year averages, incl. 2006/07/09 crops)
#         data/interim/x3_niigata_august.csv
suppressPackageStartupMessages({ library(jsonlite); library(readxl); library(rvest); library(dplyr) })
dir.create("data/interim", showWarnings = FALSE)

z2h <- function(x) chartr("０１２３４５６７８９", "0123456789", x)
num <- function(x) suppressWarnings(as.numeric(gsub("[,\\s]", "", z2h(as.character(x)), perl = TRUE)))
era_year <- function(era, n) { n <- ifelse(n == "元", "1", n); n <- as.integer(z2h(n))
  ifelse(era == "平成", 1988L + n, ifelse(era == "令和", 2018L + n, NA_integer_)) }
cells <- function(f, sheet = 1) { d <- as.data.frame(suppressMessages(
  read_excel(f, sheet = sheet, col_names = FALSE, .name_repair = "minimal")))
  d[] <- lapply(d, function(x) gsub("[\r\n 　]+", "", as.character(x))); d }

# ---------------- Y: e-Stat ----------------
v <- fromJSON("data/raw/estat/data_0003421913_tokyo_1001_1002.json")$GET_STATS_DATA$STATISTICAL_DATA$DATA_INF$VALUE
y <- v |> transmute(date = as.Date(sprintf("%s-%s-01", substr(`@time`, 1, 4), substr(`@time`, 9, 10))),
                    item = `@cat02`, value = num(`$`)) |>
  tidyr::pivot_wider(names_from = item, values_from = value) |>
  rename(y_raw = `01001`, y1002_raw = `01002`) |> arrange(date) |>
  # Item spec: before Jan 2002 the price unit was 10 kg (shinkyu table, 2002 sheet). Put on a per-5kg
  # basis by halving and flag it; a 10 kg bag is not exactly 2 x 5 kg, so the flag matters.
  mutate(unit_10kg = date < as.Date("2002-01-01"),
         y = ifelse(unit_10kg, y_raw / 2, y_raw), y1002 = ifelse(unit_10kg, y1002_raw / 2, y1002_raw))

# ---------------- X1: MAFF ----------------
man <- read.csv("data/raw/maff/manifest.csv")
man <- man[man$downloaded, ]

## (a) crop-year 速報 files: monthly all-brand average, Sep..Aug
cy_files <- man[grepl("\\.xlsx?$", man$file) & grepl("相対取引価格（速報）（.*9月～", man$title), ]
x1a <- list()
for (i in seq_len(nrow(cy_files))) {
  f <- cy_files$file[i]
  m <- regmatches(cy_files$title[i], regexec("(平成|令和)([0-9０-９元]+)年産", cy_files$title[i]))[[1]]
  crop <- era_year(m[2], m[3])
  d <- cells(f)
  hdr <- which(apply(d, 1, function(r) sum(grepl("月$", r)) >= 3))[1]
  avg <- which(apply(d, 1, function(r) any(grepl("^全銘柄平均価格$", r))))[1]
  mcols <- which(grepl("月$", unlist(d[hdr, ])))
  mon <- as.integer(z2h(sub(".*?([0-9０-９]+)月$", "\\1", unlist(d[hdr, mcols]))))
  stopifnot(identical(mon, c(9:12, 1:8)))
  x1a[[i]] <- data.frame(date = as.Date(sprintf("%d-%02d-01", ifelse(mon >= 9, crop, crop + 1L), mon)),
                         crop_year = crop, x1_raw = num(unlist(d[avg, mcols])), src = basename(f))
}
x1a <- bind_rows(x1a) |> filter(!is.na(x1_raw))

## (b) monthly releases (価格・数量（YYYY年M月）（速報）): price + volume for one month
mr_files <- man[grepl("\\.xlsx?$", man$file) & grepl("相対取引価格・数量（(平成|令和).+月）（速報）", man$title), ]
x1b <- list()
for (i in seq_len(nrow(mr_files))) {
  t <- mr_files$title[i]
  m1 <- regmatches(t, regexec("(平成|令和)([0-9０-９元]+)年産", t))[[1]]
  m2 <- regmatches(t, regexec("（(平成|令和)([0-9０-９元]+)年([0-9０-９]+)月）", t))[[1]]
  d <- cells(mr_files$file[i])
  rc <- which(matrix(grepl("^全銘柄平均価格", as.matrix(d)), nrow(d)), arr.ind = TRUE)[1, ]
  vals <- num(unlist(d[rc[1], (rc[2] + 1):ncol(d)]))
  vals <- vals[!is.na(vals)]
  x1b[[i]] <- data.frame(date = as.Date(sprintf("%d-%02d-01", era_year(m2[2], m2[3]), as.integer(z2h(m2[4])))),
                         crop_year = era_year(m1[2], m1[3]), x1_release = vals[1], volume_t = vals[2],
                         src = basename(mr_files$file[i]))
}
x1b <- bind_rows(x1b) |> arrange(date)
write.csv(x1b, "data/interim/x1_monthly_releases.csv", row.names = FALSE)

## (c) crop-year averages (年産 files), used only as a reference for crops with no monthly file
ya_files <- man[grepl("\\.xls$", man$file) & grepl("^(平成|令和)[0-9０-９元]+年産[(（]PDF", man$title), ]
x1c <- bind_rows(lapply(seq_len(nrow(ya_files)), function(i) {
  m <- regmatches(ya_files$title[i], regexec("(平成|令和)([0-9０-９元]+)年産", ya_files$title[i]))[[1]]
  d <- cells(ya_files$file[i])
  rc <- which(matrix(grepl("^全銘柄平均", as.matrix(d)), nrow(d)), arr.ind = TRUE)[1, ]
  vals <- num(unlist(d[rc[1], (rc[2] + 1):ncol(d)]))
  data.frame(crop_year = era_year(m[2], m[3]), x1_crop_avg = vals[!is.na(vals)][1], src = basename(ya_files$file[i]))
})) |> arrange(crop_year)
write.csv(x1c, "data/interim/x1_annual_crop_avg.csv", row.names = FALSE)

## combine: crop-year files first; monthly releases fill months they don't cover (e.g. 2025 crop)
x1 <- full_join(x1a |> select(date, crop_year, x1_raw),
                x1b |> select(date, crop_year_r = crop_year, x1_release, volume_t), by = "date") |>
  mutate(x1_src = case_when(!is.na(x1_raw) ~ "crop_year_file", !is.na(x1_release) ~ "monthly_release"),
         crop_year = coalesce(crop_year, crop_year_r), x1 = coalesce(x1_raw, x1_release)) |>
  select(date, x1, x1_src, x1_release, volume_t, crop_year) |> arrange(date)

# ---------------- X2: BOJ ----------------
b <- readLines("data/raw/boj/import_price_index.csv", encoding = "UTF-8")
b <- read.csv(text = b[grep("^SERIES_CODE,", b):length(b)], stringsAsFactors = FALSE)
x2 <- b |> mutate(date = as.Date(sprintf("%s-%s-01", substr(SURVEY_DATES, 1, 4), substr(SURVEY_DATES, 5, 6))),
                  value = num(VALUES)) |>
  select(date, SERIES_CODE, value) |>
  tidyr::pivot_wider(names_from = SERIES_CODE, values_from = value) |>
  transmute(date, x2_all = PRCG20_2600000000, x2_energy = PRCG20_2600520001, x2_all_2015base = PRCG15_2600000000)

# ---------------- X3: JMA ----------------
t3 <- as.data.frame(html_table(html_element(read_html("data/raw/jma/niigata_monthly_mean_temp.html"), "table.data2_s")))
aug <- t3[["8月"]]
x3y <- data.frame(year = as.integer(t3[["年"]]), aug_temp = num(gsub("[\\])×#]", "", aug)),
                  aug_flag = trimws(gsub("[-0-9. ]", "", aug)))
nml_tab <- as.data.frame(html_table(html_element(read_html("data/raw/jma/niigata_normals_1991_2020.html"), "table.data2_s")))
jma_normal_aug <- num(nml_tab[nml_tab[[1]] == "8月", 5])
our_normal <- mean(x3y$aug_temp[x3y$year %in% 1991:2020])
# Anomaly uses JMA's official 1991-2020 normal (decision 2026-11-13); our own mean is kept as a check.
x3y <- x3y |> mutate(aug_anom = aug_temp - jma_normal_aug, aug_anom_own = aug_temp - our_normal,
                     our_normal = our_normal, jma_normal = jma_normal_aug)
write.csv(x3y, "data/interim/x3_niigata_august.csv", row.names = FALSE)

## X3b: Jun-Aug precipitation total, % of JMA's 1991-2020 normal (per-year monthly_s1 pages)
pr <- bind_rows(lapply(list.files("data/raw/jma", "^niigata_monthly_s1_\\d{4}\\.html$", full.names = TRUE), function(f) {
  t <- as.data.frame(html_table(html_element(read_html(f), "table.data2_s"), header = FALSE))
  stopifnot(grepl("降水量", t[1, 4]), t[2, 4] == "合計")      # column 4 = monthly precipitation total
  t <- t[grepl("^[0-9]+$", t[[1]]), ]
  data.frame(year = as.integer(sub(".*_(\\d{4})\\.html$", "\\1", f)), month = as.integer(t[[1]]),
             precip = num(gsub("[\\])×#]", "", t[[4]])), precip_flag = trimws(gsub("[-0-9. ]", "", t[[4]])))
}))
nml_prec <- setNames(num(nml_tab[[4]]), nml_tab[[1]])          # column 4 = 降水量 合計
jja_normal_jma <- sum(nml_prec[c("6月", "7月", "8月")])
x3b_y <- pr |> filter(month %in% 6:8) |> group_by(year) |>
  summarise(jja_mm = sum(precip), n_months = sum(!is.na(precip)),
            jja_flag = paste(unique(precip_flag[precip_flag != ""]), collapse = ""), .groups = "drop") |>
  filter(n_months == 3)
jja_normal_own <- mean(x3b_y$jja_mm[x3b_y$year %in% 1991:2020])
x3b_y <- x3b_y |> mutate(jja_pct = 100 * jja_mm / jja_normal_jma, jja_pct_own = 100 * jja_mm / jja_normal_own,
                         jja_normal_jma = jja_normal_jma, jja_normal_own = jja_normal_own)
write.csv(x3b_y, "data/interim/x3b_niigata_jja_precip.csv", row.names = FALSE)

# align to crop year: weather of summer t applies to Sep t .. Aug t+1 (known by September)
x3 <- data.frame(date = seq(as.Date("1999-09-01"), as.Date("2027-08-01"), by = "month")) |>
  mutate(crop = as.integer(format(date, "%Y")) - (as.integer(format(date, "%m")) < 9)) |>
  left_join(x3y |> select(crop = year, x3 = aug_anom, x3_flag = aug_flag), by = "crop") |>
  left_join(x3b_y |> select(crop = year, x3b = jja_pct, x3b_flag = jja_flag), by = "crop") |> select(-crop)

# ---------------- X4: JNTO ----------------
jf <- "data/raw/jnto/visitor_arrivals_monthly.xlsx"
x4 <- bind_rows(lapply(excel_sheets(jf), function(sh) {
  d <- cells(jf, sh); yr <- as.integer(trimws(sh))
  hr <- which(apply(d, 1, function(r) any(r == "1月", na.rm = TRUE)))[1]
  tr <- which(d[[1]] == "総数")[1]
  mc <- which(grepl("^[0-9]+月$", unlist(d[hr, ])))
  data.frame(date = as.Date(sprintf("%d-%02d-01", yr, as.integer(sub("月", "", unlist(d[hr, mc]))))),
             x4 = num(unlist(d[tr, mc])), x4_note = paste(na.omit(unlist(d[hr - 1, mc])), collapse = ""))
})) |> arrange(date)

# ---------------- join ----------------
end_date <- max(y$date, x1$date[!is.na(x1$x1)], na.rm = TRUE)
monthly <- y |> select(date, y, y_raw, unit_10kg, y1002) |>
  full_join(x1, by = "date") |> left_join(x2, by = "date") |>
  left_join(x3, by = "date") |> left_join(x4 |> select(date, x4), by = "date") |>
  filter(date >= as.Date("2000-01-01"), date <= end_date) |>
  arrange(date)
write.csv(monthly, "data/interim/monthly.csv", row.names = FALSE)

cat("Y   :", format(range(y$date)), nrow(y), "rows\n")
cat("X1  :", format(range(x1$date[!is.na(x1$x1)])), sum(!is.na(x1$x1)), "months;",
    "crop-year files for crops", paste(sort(unique(x1a$crop_year)), collapse = ","), "\n")
cat("X1 monthly releases:", nrow(x1b), "files,", format(range(x1b$date)), "\n")
cat("X1 crop averages for crops:", paste(x1c$crop_year, collapse = ","), "\n")
cat("X2  :", format(range(x2$date[!is.na(x2$x2_all)])), "\n")
cat("X3  : Aug normal ours", round(our_normal, 2), "vs JMA", jma_normal_aug, "| X3b: JJA normal ours", round(jja_normal_own, 1), "mm vs JMA", jja_normal_jma, "mm;", nrow(x3b_y), "years\n")
cat("X4  :", format(range(x4$date[!is.na(x4$x4)])), "\n")
cat("monthly.csv:", nrow(monthly), "rows; duplicated dates:", sum(duplicated(monthly$date)), "\n")
