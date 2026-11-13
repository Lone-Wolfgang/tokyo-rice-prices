# Pull X2: BOJ Import Price Index, yen basis, 2020 base (BOJ links history back to 1960).
#   PRCG20_2600000000  All commodities
#   PRCG20_2600520001  Petroleum, coal and natural gas
# Also the 2015-base all-commodities series, to check rebasing consistency on the overlap.
# Uses the BOJ Time-Series Data Search API (no key needed).
library(httr2)
dir.create("data/raw/boj", recursive = TRUE, showWarnings = FALSE)

codes <- c("PRCG20_2600000000", "PRCG20_2600520001", "PRCG15_2600000000")
resp <- request("https://www.stat-search.boj.or.jp/api/v1/getDataCode") |>
  req_url_query(format = "csv", lang = "en", db = "PR01",
                startDate = "199901", endDate = "202612", code = paste(codes, collapse = ",")) |>
  req_retry(max_tries = 3) |>
  req_perform(path = "data/raw/boj/import_price_index.csv")
message("saved data/raw/boj/import_price_index.csv")

# metadata (series names/units) is large; only refetch if missing
if (!file.exists("data/raw/boj/meta_PR01.json"))
  request("https://www.stat-search.boj.or.jp/api/v1/getMetadata") |>
    req_url_query(format = "json", lang = "en", db = "PR01") |>
    req_perform(path = "data/raw/boj/meta_PR01.json")
