# Pull X3: JMA past weather data, Niigata (prec_no 54, block_no 47604).
#   monthly_s3.php     : monthly mean temperature, all years (one row per year)
#   nml_sfc_ym.php     : official 1991-2020 normals (平年値), to check our computed normal
library(httr2)
dir.create("data/raw/jma", recursive = TRUE, showWarnings = FALSE)
base <- "https://www.data.jma.go.jp/stats/etrn/view/"
get <- function(page, out) {
  request(paste0(base, page)) |>
    req_url_query(prec_no = 54, block_no = 47604, year = "", month = "", day = "", view = "") |>
    req_user_agent("Mozilla/5.0 (research; rice EDA)") |>
    req_retry(max_tries = 3) |> req_perform(path = out)
  message("saved ", out); Sys.sleep(1)
}
get("monthly_s3.php", "data/raw/jma/niigata_monthly_mean_temp.html")
get("nml_sfc_ym.php", "data/raw/jma/niigata_normals_1991_2020.html")

# Per-year pages (all elements, incl. monthly precipitation totals) for 1991-2026.
# monthly_s3 only shows temperature, so precipitation comes from these.
for (yr in 1991:2026) {
  out <- sprintf("data/raw/jma/niigata_monthly_s1_%d.html", yr)
  if (file.exists(out) && yr < as.integer(format(Sys.Date(), "%Y"))) next  # past years don't change
  request(paste0(base, "monthly_s1.php")) |>
    req_url_query(prec_no = 54, block_no = 47604, year = yr, month = "", day = "", view = "") |>
    req_user_agent("Mozilla/5.0 (research; rice EDA)") |>
    req_retry(max_tries = 3) |> req_perform(path = out)
  Sys.sleep(1)
}
message("saved yearly pages 1991-2026")
