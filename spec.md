# Japanese Rice Price Forecasting — Data & Modelling Spec

Oct 20, 2026 · @Wolf

## Project overview

Forecast the monthly retail price of a 5 kg bag of Koshihikari rice in Tokyo's 23 wards, 3 and 12 months ahead, so a Tokyo restaurant group can decide whether to lock in a 12-month supply contract now or keep buying at spot.

- **Client question:** Will retail rice prices fall enough over the next year to justify waiting, or should we fix a contract price now?
- **Response:** Retail Price Survey item 1001, *uruchi-mai* (single-origin Koshihikari, 5 kg bag), Tokyo ku-area, yen per bag, monthly from January 2000 to the latest released month (about 320 observations).
- **Short horizon:** 3 months (Q4 2026). This is the spot-buying window.
- **Long horizon:** 12 months (through roughly September 2027). This is the contract length, and it spans the 2027 harvest.

The series is longer than first feared: 26+ years of monthly data, not just the post-2022 POS series. Retail prices roughly doubled between May 2024 and May 2025 and have stayed on a high plateau since, so the break is the main modelling challenge.

The long horizon also crosses a planned tax change. The Cabinet approved cutting the consumption tax on food from 8% to 1% for two years from 1 April 2027, pending legislation. The spec handles this by modelling tax-exclusive prices (see Data preparation).

## Data collection

The original plan had three explanatory variables. This spec adds the wholesale rice price as the main one, because it is the most direct leading indicator of retail price.

| Role | Series | Source | Frequency | Coverage | Units |
| --- | --- | --- | --- | --- | --- |
| Response (Y) | Retail price, item 1001 Koshihikari 5 kg, Tokyo ku-area | [Retail Price Survey (Trend), e-Stat table 主要品目の都市別小売価格](https://www.stat.go.jp/data/kouri/doukou/change/change202601.html) | Monthly | Jan 2000 → latest | ¥ per bag, tax-inclusive |
| X1 (lead) | Relative trading price, all-brand average (相対取引価格 全銘柄平均) | [MAFF rice trading prices](http://www.maff.go.jp/j/seisan/keikaku/soukatu/aitaikakaku.html) | Monthly, by crop year (Sep–Aug) | Comparable from the 1990 crop | ¥ per 60 kg brown rice, tax-inclusive |
| X2 (cost) | Import price index, yen basis (all commodities, or petroleum, coal and natural gas) | Bank of Japan Time-Series Data Search | Monthly | Jan 2000 → latest | Index |
| X3 (weather) | August mean temperature anomaly at Niigata | JMA past weather data (過去の気象データ) | Annual, held for the crop year | 2000 → 2026 | °C vs. normal |
| X4 (optional) | Foreign visitor arrivals | JNTO | Monthly | Jan 2000 → latest | Persons |

Why these variables:

- **X1** is the price wholesalers pay collection groups such as JA. It moves before shelf prices and carries supply shocks directly.
- **X2** proxies fuel, fertilizer and freight costs. It also captures yen weakness.
- **X3** captures crop quality. The government white paper blamed poor milling yield after the extreme heat of 2023 as one cause of the shortage ([nippon.com](https://www.nippon.com/en/japan-data/h02811/)).
- **X4** is optional. The same white paper cited tourist demand, but the 2020–22 collapse to near zero makes it awkward. Include it only if it survives the VAR lag and Granger checks.

Retrieval steps:

1. **Y:** On e-Stat, open 小売物価統計調査 › 動向編 › 主要品目の都市別小売価格 (the monthly city-level series, available from January 2000). Select item 1001 and area 東京都区部, then download as CSV. The e-Stat API is an alternative if you want a reproducible pull.
2. **X1:** From the MAFF page, download the monthly Excel or CSV for each crop year. Earlier years are on the linked page for past releases (過去に公表した相対取引価格等). Take the 全銘柄平均 row only.
3. **X2:** In BOJ Time-Series Data Search, choose Prices › Import Price Index › yen basis, then export monthly CSV.
4. **X3:** In JMA past weather data, pick station Niigata, monthly values, August mean temperature, 2000–2026. Compute the anomaly against the 1991–2020 normal.
5. **X4 (optional):** Download monthly visitor arrivals from JNTO statistics.
6. Save each raw file unchanged in `data/raw/` and record the download date in a README, since several of these series get revised.

## Data preparation

Model the tax-exclusive log price, then add tax back at the end. This removes the 2014 tax jump from history and lets the forecast handle the planned April 2027 cut as a scenario.

1. **Strip consumption tax from Y and X1.** Divide by 1.05 for months before April 2014 and by 1.08 from April 2014 onward. Food stayed at 8% under the reduced rate after October 2019, so no adjustment is needed there.
2. **Log-transform** Y, X1, X2 and X4. Leave X3 in °C.
3. **Build a continuous X1.** MAFF publishes each crop year separately (September to August). For each calendar month, use the current crop year's price. If the first month of a new crop is missing or very thin, carry forward the previous month and flag it.
4. **Align X3 with the crop year.** The August anomaly for year *t* applies to September *t* through August *t+1*. That way it is known at forecast time and does not leak future information.
5. **Add intervention dummies:**
   - Benchmark specification revisions in January 2007 and January 2012. The Statistics Bureau notes these on its charts, and they can cause level shifts.
   - A shortage-regime indicator from August 2024 onward. The white paper links the start of panic buying to the Nankai Trough earthquake advisory that month.
6. **Join** all series on month and trim to the common window (January 2000 → latest month that has both Y and X1).
7. **Hold out** the last 12 months for the long-horizon ASE. The short-horizon ASE uses the first 3 of those months.
8. **Run a sensitivity fit** on January 2000 – July 2024 (pre-shortage). Report how much the post-2024 data changes the model order and coefficients.

Document every choice in step 1 and step 5 in the Rmd, because the grader will look for justification of the structural-break handling.

## Exploratory analysis

The EDA must show enough to justify every model order you pick. The rubric explicitly asks for ACFs, spectral densities and factor tables.

| Plot or test | Applied to | What to look for | R (tswge unless noted) |
| --- | --- | --- | --- |
| Realization, sample ACF, Parzen spectral density | log Y | Slowly decaying ACF (wandering); any peak at frequency 1/12 (new-crop season) | `plotts.sample.wge` |
| Overfit AR(15) factor table | log Y | Roots near 1 (difference needed); roots on the unit circle at 1/12 (seasonal) | `est.ar.wge(p = 15)`, `factor.wge` |
| Same three plots after differencing | Δ log Y, and Δ₁₂ if indicated | ACF dies quickly; flat or ARMA-shaped spectrum | `artrans.wge`, `plotts.sample.wge` |
| Unit-root test | log Y, log X1 | Supports or rejects differencing | `tseries::adf.test` |
| Cross-correlation function | Δ log Y vs. Δ log X1, Δ log X2 | Which lag of X leads Y (expect wholesale to lead retail by 1–3 months) | `ccf` |
| Overlay of log Y and log X1 | Levels | Whether they move together (cointegration hint) | `ggplot2` |
| Zoom on 2024–2026 | log Y, log X1 | Size and shape of the break; whether prices are mean-reverting yet | `ggplot2` |

Expect weak seasonality. Rice is a stored grain, so retail prices are smoother than for fresh produce. If the factor table shows no seasonal roots, say so explicitly and use plain ARIMA. A null result here is still evidence the grader wants to see.

## Modelling plan

Fit one model per rubric category on the tax-exclusive log price. Each model below names a primary candidate and one alternative to compare.

| Category | Primary model | Alternative | Identification | Key R calls |
| --- | --- | --- | --- | --- |
| (a) Univariate | ARIMA(p,1,q) on log Y | ARUMA with (1 − B¹²) if seasonal roots appear; signal plus noise (linear trend + AR) as a contrast | `aic5.wge` on the differenced series; residual Ljung-Box test | `est.arma.wge`, `fore.arima.wge`, `ljung.wge` |
| (b) VAR | VAR on Δ log Y, Δ log X1, Δ log X2 | Add X4 if it Granger-causes Y | Lag order from `VARselect` (BIC); X3 and dummies as exogenous terms | `vars::VAR(exogen = …)`, `causality`, `serial.test` |
| (c) Neural network | `nnfor::mlp` on log Y with lagged X1 and X2 as `xreg` | Univariate MLP with no regressors | Let `mlp` choose lags and differencing; fix the seed; use 20 repetitions | `nnfor::mlp`, `forecast` |
| (d) Ensemble | Equal-weight average of the VAR and MLP forecasts | Inverse-ASE weights across all three | Weights from rolling-window ASE on the training period only | Base R |

Details that matter:

- **VAR cointegration.** If log Y and log X1 look cointegrated, a VAR in differences discards that long-run link. Mention a VECM as a possible extension, but keep the VAR as the graded model.
- **Future regressor values.** The MLP needs future X values for a 12-month forecast. Feed it the VAR's forecasts of X1 and X2 so the two models are consistent. Otherwise use lags of at least the horizon length.
- **X3 at forecast time.** The August 2026 anomaly is already known, so it covers the whole forecast window up to August 2027. For September 2027, assume a zero anomaly.
- **Dummies in forecasts.** Set the shortage-regime dummy to 1 for all future months, and state that assumption.

## Evaluation and forecasts

Compare all four models on ASE in yen, on the original tax-exclusive scale, at both horizons. Pick the final model on rolling-window ASE plus how sensible its forecast looks, not on single-holdout ASE alone.

1. **Holdout ASE.** Use the last 3 months for the short horizon and the last 12 months for the long horizon. Back-transform with `exp()` before computing ASE.
2. **Rolling-window ASE.** Use a 120-month training window, step forward 1 month, and forecast h = 3 and h = 12 from each origin. `tswge::roll.win.rmse.wge` covers the univariate model. Write a small loop for the VAR, MLP and ensemble. Report the mean and the spread across windows.
3. **Two error regimes.** Report rolling ASE separately for origins before and after August 2024. This keeps the break from hiding which model is better in normal times.
4. **Final forecasts.** Refit the chosen models on all data. Forecast 3 and 12 months ahead with 95% prediction limits. For the ensemble, take limits from the empirical quantiles of its rolling-window errors.
5. **Put tax back as two scenarios.** Multiply by 1.08 through March 2027. From April 2027, use 1.01 if the food tax cut passes and 1.08 if it doesn't. That is a mechanical drop of about 6.5% (1.01 / 1.08), separate from anything the models predict.

Results table to fill in:

| Model | ASE, h = 3 | Rolling ASE, h = 3 | ASE, h = 12 | Rolling ASE, h = 12 |
| --- | --- | --- | --- | --- |
| ARIMA / ARUMA |  |  |  |  |
| VAR |  |  |  |  |
| MLP |  |  |  |  |
| Ensemble |  |  |  |  |

The client answer is the last line of the deck: the 12-month forecast path with its limits, under both tax scenarios, compared with the price on offer in a fixed contract.

## Deliverables and risks

The submission is an Rmd, a slide deck, and a 7-minute video linked on the class Google Doc.

- [ ] Raw data pulled and README written (week 1)
- [ ] Cleaned, tax-adjusted, aligned dataset (week 1)
- [ ] EDA plots and factor tables (week 2)
- [ ] ARIMA/ARUMA and VAR fitted, residuals checked (week 2)
- [ ] MLP and ensemble fitted (week 3)
- [ ] ASE and rolling-window ASE table complete (week 3)
- [ ] Final forecasts with limits under both tax scenarios (week 3)
- [ ] Slides and 7-minute video, posted to YouTube as unlisted (week 4)
- [ ] Rmd and slides submitted; link on the Google Doc for a week; 3 peer videos watched (week 4)

| Risk | Effect | Mitigation |
| --- | --- | --- |
| The 2024–25 break dominates every error metric | Rankings reflect one shock, not general skill | Split rolling ASE into pre- and post-break; run the pre-break sensitivity fit |
| The MAFF crop-year files need manual stitching | Slow data assembly, possible gaps at the September switchover | Script the merge early; flag carried-forward months |
| The food tax cut changes or fails in the Diet | The long-horizon forecast is off by about 6.5% from April 2027 | Model tax-exclusive prices; present both scenarios |
| The VAR shows weak Granger causality from X2 or X4 | Weak story for category (b) | X1 should carry the VAR; report the weak ones honestly |
| Benchmark specification revisions shift the level | Spurious structure in the ACF or factor table | Dummies for January 2007 and January 2012 |

**Open question:** confirm with the instructor that tax-exclusive modelling with tax re-applied afterwards is acceptable, rather than modelling the published tax-inclusive price.

## Sources

- [Statistics Bureau: Retail Price Survey table structure (2026)](https://www.stat.go.jp/data/kouri/doukou/change/change202601.html)
- [NDL guide to Retail Price Survey e-Stat tables (monthly city series from 2000)](https://ndlsearch.ndl.go.jp/rnavi/business/post_102125)
- [MAFF: rice relative trading prices and quantities](http://www.maff.go.jp/j/seisan/keikaku/soukatu/aitaikakaku.html)
- [nippon.com: Soaring rice prices and the 2025 food white paper](https://www.nippon.com/en/japan-data/h02811/)
- [Keidanren notice on the food consumption tax cut (Sep 2026)](https://www.keidanren.or.jp/announce/2026/0929.html)

## Revisions after data checks (2026-11-13)

The data checks in `sanity_checks.html` found that several assumptions above don't hold. The original text is left unchanged; these decisions replace it where they conflict.

| Topic | Original spec | Revised decision | Reason |
| --- | --- | --- | --- |
| Sample window | Jan 2000 → latest (about 320 months) | **Sep 2010 → latest, for all models** (193 months to Sep 2026) | MAFF's 相対取引価格 starts with the 2006 crop, and monthly files exist only for the 2008 crop and from 2010 on |
| Y before 2002 | – | Out of window. For reference, e-Stat's Jan 2000 – Dec 2001 values are per 10 kg | Item 1001 changed from 10 kg to a 5 kg bag in Jan 2002 |
| Intervention dummies | Jan 2007, Jan 2012, shortage from Aug 2024 | **Shortage from Aug 2024 only** | The Statistics Bureau's spec-revision tables show no change to item 1001 in 2007 or 2012 |
| Weather | X3 = Niigata August temperature anomaly | X3 as before, plus **X3b = Niigata Jun–Aug precipitation, % of the 1991–2020 normal**, held for the crop year. Both use JMA's official normals | Aug 2023 was the hottest (30.6 °C) and nearly the driest (2.0 mm) August on record |
| Evaluation | Holdout ASE plus rolling ASE, 120-month window | Last-12-month holdout **plus** rolling ASE with a **96-month** training window, step 1, h = 3 and 12, split by origin before/after Aug 2024 | With data from 2010, 120 months leaves too few origins. 96 gives 72 pre-break origins per horizon |
| Sensitivity fit | Jan 2000 – Jul 2024 | Sep 2010 – Jul 2024 | Follows the window |
| X1 behaviour | Monthly leading indicator | Mostly a once-a-year step at the September new-crop repricing. Model data carries a `sep` indicator. The VECM is promoted to a parallel check | 59% of absolute monthly X1 change since 2010 happens in September |
| Macro drivers (JPY/USD, crude oil in USD) | Not in spec | **Considered and not added.** X2 already covers both | X2 jumped 49% year on year in Sep 2022 (energy +123%) with rice flat; rice jumped 42–89% in 2024–25 with X2 flat or falling; X2 has no pre-break lead on Y (\|r\| ≤ 0.07) |
| Latest X1 month | – | Sep 2026 is thin (54k t) and preliminary. Re-pull when MAFF publishes October, before final modelling | Pending as of 2026-11-13 |

Model-ready data: `data/processed/model_data.csv` and `data/processed/splits.rds`, built by `R/20_prepare_model_data.R`.
