# Data

All files in `raw/` are saved exactly as downloaded. **Download date for everything: 2026-11-13.**
Several of these series get revised (MAFF 速報, JNTO 推計値), so re-run the pull scripts and note the new date before final modelling.

Re-create everything from the project root:

```sh
Rscript R/01_pull_y_estat.R   # needs ESTAT_APPID in ~/.Renviron
Rscript R/02_pull_x1_maff.R
Rscript R/03_pull_x2_boj.R
Rscript R/04_pull_x3_jma.R
Rscript R/05_pull_x4_jnto.R
Rscript R/10_parse_join.R     # -> interim/*.csv
Rscript R/20_prepare_model_data.R  # -> processed/model_data.csv, splits.rds
Rscript R/40_placeholder_forecasts.R  # -> processed/forecasts_placeholder.json
Rscript R/30_export_dashboard.R    # -> docs/data.json (dashboard)
Rscript -e 'rmarkdown::render("sanity_checks.Rmd")'
```

## Sources

| Series | Raw file(s) | Source / identifiers | Units | Notes |
|---|---|---|---|---|
| **Y** retail price | `raw/estat/data_0003421913_tokyo_1001_1002.json`, `meta_0003421913.json` | e-Stat API v3, statsDataId **0003421913** (小売物価統計調査 動向編, 主要品目の都市別小売価格, 2000年1月～), cat02 **01001** (うるち米 単一原料米「コシヒカリ」) and 01002 (コシヒカリ以外, kept for comparison), area **13100** (特別区部) | ¥ per bag, tax-inclusive | **Jan 2000 – Dec 2001 values are per 10 kg**: spec revised to a 5 kg bag in Jan 2002. The parser halves them and sets `unit_10kg`. |
| Y spec history | `raw/estat/shinkyu_meigara_2001_2026.xlsx` | stat.go.jp 基本銘柄の新旧対照表 2001–2026 | – | Item 1001 revised only Jan 2002 (unit) and Nov 2009 (wording). |
| **X1** wholesale | `raw/maff/files/*`, `raw/maff/manifest.csv`, `raw/maff/*_page.html` | MAFF 米の相対取引価格 (current page `aitaikakaku.html`, past page `kakaku.html`). The manifest maps each file to its link title. | ¥ per 60 kg brown rice, **tax-inclusive** (税込) | Crop-year monthly files for the 2008 crop and 2010–2024 crops; 2025 crop from 12 monthly releases; 2026 crop = Sep 2026 only (速報). 2006/2007/2009 crops: crop-year averages only. Series starts with the 2006 crop. |
| **X2** import prices | `raw/boj/import_price_index.csv`, `meta_PR01.json` | BOJ Time-Series Data Search API, db PR01: **PRCG20_2600000000** (all commodities, yen basis, 2020=100), **PRCG20_2600520001** (petroleum, coal & natural gas), PRCG15_2600000000 (2015 base, rebasing check) | Index | Linked back to 1960 by BOJ. |
| **X3** temperature | `raw/jma/niigata_monthly_mean_temp.html`, `niigata_normals_1991_2020.html` | JMA 過去の気象データ, Niigata (prec_no 54, block_no 47604): monthly_s3 (monthly means, all years) and nml_sfc_ym (1991–2020 normals) | °C | Anomaly against JMA's official August normal (26.5 °C); our computed 1991–2020 mean is 26.61 °C. |
| **X3b** precipitation | `raw/jma/niigata_monthly_s1_YYYY.html` (1991–2026) | JMA monthly_s1 per-year pages, Niigata: column 降水量 合計 | % of normal | Jun–Aug total ÷ JMA's Jun–Aug normal (506.8 mm). The current year's page is re-downloaded on each run. |
| **X4** visitors | `raw/jnto/visitor_arrivals_monthly.xlsx`, `source_url.txt` | JNTO 国籍/月別 訪日外客数 (2003–2026), row 総数 | Persons | Starts 2003, not 2000. Recent months are estimates (推計値). |

## Interim outputs (`interim/`)

- `monthly.csv`: one row per month, Jan 2000 – Sep 2026. Tax-inclusive, untransformed. `y` is on a per-5kg basis; `y_raw` is as published. `x1_src` gives the X1 source file type. `x3` is already aligned to the crop year (August of year *t* → Sep *t* … Aug *t+1*).
- `x1_monthly_releases.csv`: MAFF monthly releases (price and traded volume in tonnes), 2022 crop onward.
- `x1_annual_crop_avg.csv`: crop-year average X1 for 2006–2024 crops.
- `x3_niigata_august.csv`: August temperatures 1881–2026, anomalies against JMA's normal (`aug_anom`) and ours (`aug_anom_own`).
- `x3b_niigata_jja_precip.csv`: Jun–Aug precipitation 1991–2026, % of JMA's normal and of ours.

## Processed outputs (`processed/`)

- `model_data.csv`: Sep 2010 → latest. Tax-exclusive logs `ly`, `lx1`; `lx2` (and `lx2_energy`); `x3_temp`; `x3b_precip`; `lx4`; dummies `shortage` (Aug 2024 on) and `sep`; X1 flags `x1_thin` and `x1_prelim`.
- `splits.rds`: holdout indices (last 12 months, plus the first 3 of those for the short horizon), rolling origins (96-month training window; h = 3 and 12; regime; `pre_holdout` marks origins usable for ensemble weights), and the pre-break sensitivity window.

**Pending:** MAFF's October 2026 release wasn't out on 2026-11-13. When it is, re-run `R/02` → `R/10` → `R/20` and re-knit.
