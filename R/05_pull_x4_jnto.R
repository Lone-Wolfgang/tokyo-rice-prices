# Pull X4: JNTO visitor arrivals by nationality/month (2003-2026), one sheet per year.
# The file name on JNTO changes with each release; the link is located by its label.
library(httr2)
dir.create("data/raw/jnto", recursive = TRUE, showWarnings = FALSE)
page <- "https://www.jnto.go.jp/statistics/data/visitors-statistics/"
request(page) |> req_user_agent("Mozilla/5.0") |> req_perform(path = "data/raw/jnto/visitors_page.html")
s <- paste(readLines("data/raw/jnto/visitors_page.html", encoding = "UTF-8", warn = FALSE), collapse = "\n")
m <- regmatches(s, gregexpr('<a [^>]*href="[^"]+\\.xlsx"[^>]*>.*?</a>', s, perl = TRUE))[[1]]
m <- m[grepl("月別", m)]
stopifnot(length(m) >= 1)
href <- sub('.*href="([^"]+)".*', "\\1", m[1])
url <- paste0("https://www.jnto.go.jp", href)
request(url) |> req_user_agent("Mozilla/5.0") |>
  req_perform(path = "data/raw/jnto/visitor_arrivals_monthly.xlsx")
writeLines(c(url, as.character(Sys.Date())), "data/raw/jnto/source_url.txt")
message("saved data/raw/jnto/visitor_arrivals_monthly.xlsx from ", url)
