# Pull X1: MAFF relative trading prices (相対取引価格). Downloads the current page, the
# past-releases page, and every Excel/CSV/PDF attachment linked from them, unchanged.
# Writes a manifest (file, link text, url) so the parser can pick files by their label.
library(httr2)
dir.create("data/raw/maff/files", recursive = TRUE, showWarnings = FALSE)

pages <- c(current = "https://www.maff.go.jp/j/seisan/keikaku/soukatu/aitaikakaku.html",
           past    = "https://www.maff.go.jp/j/seisan/keikaku/soukatu/kakaku.html")

fetch <- function(url, out) {
  if (file.exists(out)) return(invisible(out))
  request(url) |> req_user_agent("Mozilla/5.0 (research; rice EDA)") |>
    req_retry(max_tries = 3) |> req_perform(path = out)
  Sys.sleep(0.5)  # be polite to the server
  invisible(out)
}

manifest <- list()
for (nm in names(pages)) {
  html_path <- sprintf("data/raw/maff/%s_page.html", nm)
  unlink(html_path); fetch(pages[[nm]], html_path)
  s <- paste(readLines(html_path, encoding = "UTF-8", warn = FALSE), collapse = "\n")
  m <- regmatches(s, gregexpr('<a [^>]*href="([^"]+)"[^>]*>(.*?)</a>', s, perl = TRUE))[[1]]
  href <- sub('.*href="([^"]+)".*', "\\1", m)
  text <- trimws(gsub("<[^>]+>|&nbsp;", "", sub('^<a [^>]*>(.*)</a>$', "\\1", m)))
  keep <- grepl("\\.(xlsx?|csv|pdf)$", href) & !grepl("^https?://", href)
  # attach labels: Excel/CSV links are labelled "Excel(...)"; inherit the title of the preceding PDF
  title <- text
  for (i in seq_along(title)) if (grepl("^(Excel|CSV)", title[i]) && i > 1) title[i] <- title[i - 1]
  for (i in which(keep)) {
    url <- if (startsWith(href[i], "/")) paste0("https://www.maff.go.jp", href[i]) else
      paste0(dirname(pages[[nm]]), "/", sub("^\\./", "", href[i]))
    out <- file.path("data/raw/maff/files", paste0(nm, "_", gsub("[/.]+", "_", sub("^\\./", "", href[i])),
                                                  ".", tools::file_ext(href[i])))
    manifest[[length(manifest) + 1]] <- data.frame(page = nm, file = out, title = title[i],
                                                   link_text = text[i], url = url)
  }
}
manifest <- unique(do.call(rbind, manifest))
# Only download spreadsheets/CSVs plus the reference PDFs (long-run price trend etc.)
want <- grepl("\\.(xlsx?|csv)$", manifest$file) | grepl("参考", manifest$title)
for (i in which(want)) fetch(manifest$url[i], manifest$file[i])
manifest$downloaded <- file.exists(manifest$file)
manifest$download_date <- as.character(Sys.Date())
write.csv(manifest, "data/raw/maff/manifest.csv", row.names = FALSE, fileEncoding = "UTF-8")
message(sum(manifest$downloaded), " files downloaded of ", nrow(manifest), " links")
