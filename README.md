# Tokyo rice prices

Forecasting the monthly retail price of a 5 kg bag of Koshihikari rice in Tokyo's 23 wards, 3 and 12 months ahead, so a Tokyo restaurant group can decide whether to lock in a 12-month supply contract or keep buying at spot.

**Dashboard:** https://lone-wolfgang.github.io/tokyo-rice-prices/ (source in `docs/`).

## Contents

| Path | What it is |
|---|---|
| `spec.md` | Project spec, plus the revisions made after the data checks |
| `sanity_checks.Rmd` / `.html` | Data checks against the spec's assumptions, with the go/revise call |
| `R/0*_pull_*.R` | Download each source into `data/raw/` unchanged |
| `R/10_parse_join.R` | Parse and join into `data/interim/monthly.csv` |
| `R/20_prepare_model_data.R` | Model-ready data and evaluation splits (`data/processed/`) |
| `R/30_export_dashboard.R` | Writes `docs/data.json` for the dashboard |
| `docs/` | The dashboard: static HTML/CSS/JS reading `data.json` |
| `data/README.md` | Sources, identifiers, units, download dates |

## Rebuild

```sh
# e-Stat needs a free appId in ~/.Renviron:  ESTAT_APPID=...
Rscript R/01_pull_y_estat.R
Rscript R/02_pull_x1_maff.R
Rscript R/03_pull_x2_boj.R
Rscript R/04_pull_x3_jma.R
Rscript R/05_pull_x4_jnto.R
Rscript R/10_parse_join.R
Rscript R/20_prepare_model_data.R
Rscript R/30_export_dashboard.R
Rscript -e 'rmarkdown::render("sanity_checks.Rmd")'
```

Preview the dashboard locally with `python3 -m http.server --directory docs` and open http://localhost:8000.

## Data

All public: Statistics Bureau Retail Price Survey (e-Stat), MAFF rice trading prices, Bank of Japan import price index, JMA weather data (Niigata) and JNTO visitor arrivals. See `data/README.md`.
