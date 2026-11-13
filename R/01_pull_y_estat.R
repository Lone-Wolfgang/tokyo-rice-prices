# Pull Y: Retail Price Survey (Trend), item 1001 Koshihikari 5kg, Tokyo ku-area.
# Table 0003421913: 主要品目の都市別小売価格 (2000年1月～). Requires ESTAT_APPID in ~/.Renviron.
# Also pulls item 1002 (non-Koshihikari single-origin) and the national monthly table as cross-checks.
library(httr2)
k <- Sys.getenv("ESTAT_APPID")
stopifnot(nchar(k) > 0)
dir.create("data/raw/estat", recursive = TRUE, showWarnings = FALSE)

base <- "https://api.e-stat.go.jp/rest/3.0/app/json/"
get <- function(endpoint, ..., out) {
  resp <- request(paste0(base, endpoint)) |>
    req_url_query(appId = k, ...) |>
    req_retry(max_tries = 3) |>
    req_perform()
  writeLines(resp_body_string(resp), out)
  message("saved ", out)
}

get("getMetaInfo", statsDataId = "0003421913", out = "data/raw/estat/meta_0003421913.json")
get("getStatsData", statsDataId = "0003421913", cdCat02 = "01001,01002", cdArea = "13100",
    out = "data/raw/estat/data_0003421913_tokyo_1001_1002.json")

# Item-specification revision history (基本銘柄の新旧対照表, 2001-2026), from the Statistics Bureau.
# Used to check for level shifts caused by spec changes (e.g. 10 kg -> 5 kg bag in Jan 2002).
request("https://www.stat.go.jp/data/kouri/doukou/zuhyou/shinkyu.xlsx") |>
  req_user_agent("Mozilla/5.0") |> req_perform(path = "data/raw/estat/shinkyu_meigara_2001_2026.xlsx")
message("saved data/raw/estat/shinkyu_meigara_2001_2026.xlsx")
