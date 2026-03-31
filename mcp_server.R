suppressPackageStartupMessages({
  library(ellmer)
  library(mcptools)
  library(tidyverse)
  library(jsonlite)
  library(DBI)
  library(bigrquery)
})

SCHEMA_DIR <- Sys.getenv("SCHEMA_DIR", "/data")

# Use application default credentials (gcloud ADC mounted in Docker).
# Suppresses interactive OAuth prompts in non-interactive containers.
bq_auth(token = gargle::credentials_app_default(
  scopes = c(
    "https://www.googleapis.com/auth/bigquery",
    "https://www.googleapis.com/auth/cloud-platform"
  )
))

read_jsonl <- function(path) {
  con <- file(path, "r")
  on.exit(close(con))
  stream_in(con, verbose = FALSE)
}

all_data <- function() {
  list.files(SCHEMA_DIR, full.names = TRUE, pattern = "\\.jsonl$") |>
    map(read_jsonl) |>
    list_rbind()
}

orion_list_datasets <- function() {
  all_data() |>
    summarise(
      dataset_description = first(dataset_description),
      tables = n(),
      .by = c(project, dataset)
    ) |>
    toJSON(auto_unbox = TRUE, pretty = TRUE)
}

orion_list_tables <- function(project, dataset) {
  all_data() |>
    filter(.data$project == .env$project, .data$dataset == .env$dataset) |>
    select(table, description) |>
    toJSON(auto_unbox = TRUE, pretty = TRUE)
}

strip_nested_descriptions <- function(schema) {
  if ("fields" %in% names(schema)) {
    schema$fields <- map(schema$fields, \(f) {
      if (is.data.frame(f)) select(f, -any_of("description")) |> strip_nested_descriptions()
      else f
    })
  }
  schema
}

orion_get_db_schema <- function(project, dataset, table) {
  result <- all_data() |>
    filter(.data$project == .env$project, .data$dataset == .env$dataset, .data$table == .env$table)

  if (nrow(result) == 0) stop("Not found: ", project, "/", dataset, "/", table)

  result$schema[[1]] |>
    strip_nested_descriptions() |>
    toJSON(auto_unbox = TRUE, pretty = TRUE)
}

orion_estimate_query_cost <- function(sql) {
  billing <- Sys.getenv("BQ_BILLING_PROJECT")
  if (billing == "") stop("BQ_BILLING_PROJECT environment variable not set")

  bytes <- as.numeric(bq_perform_query_dry_run(sql, billing = billing))
  gb <- round(bytes / 1e9, 3)

  list(
    bytes_processed = bytes,
    gb_processed = gb,
    within_sandbox_free_tier = gb < 1000,
    message = glue::glue(
      "This query will scan {gb} GB. The free tier includes 1 TB/month."
    )
  ) |> toJSON(auto_unbox = TRUE, pretty = TRUE)
}

orion_run_bq_query <- function(sql) {
  if (grepl("SELECT\\s+\\*", sql, ignore.case = TRUE)) {
    stop(
      "SELECT * is not allowed — ",
      "specify only the columns needed to avoid scanning unnecessary data."
    )
  }

  billing <- Sys.getenv("BQ_BILLING_PROJECT")
  if (billing == "") stop("BQ_BILLING_PROJECT environment variable not set")

  con <- dbConnect(bigquery(), project = billing)
  on.exit(dbDisconnect(con))

  result <- dbGetQuery(con, sql)
  toJSON(result, auto_unbox = TRUE, pretty = TRUE)
}

mcp_server(
  tools = list(
    tool(
      orion_list_datasets,
      "List all ORION-DBs datasets available on BigQuery from various providers of open research information. Does NOT return schemas, but gives a brief overview. For more info see <https://orion-dbs.community/>"
    ),
    tool(
      orion_list_tables,
      "List all tables in a specific project/dataset with descriptions from ORION-DBs. Drill into a BQ dataset before fetching a schema.",
      project = type_string("The GCP project ID"),
      dataset = type_string("The BigQuery dataset name")
    ),
    tool(
      orion_get_db_schema,
      "Get the full BigQuery schema for a specific table. Only call when user explicitly wants to query or understand a table structure. Thsi is also helpful when comparing different datasets and tables on ORION.",
      project = type_string("The GCP project ID"),
      dataset = type_string("The BigQuery dataset name"),
      table = type_string("The BigQuery table name")
    ),
    tool(
      orion_estimate_query_cost,
      paste(
        "Estimate bytes scanned by a query before running it.",
        "Always call this before run_query.",
        "Only accurate when query selects specific columns, not SELECT *."
      ),
      sql = type_string("The BigQuery SQL query to dry-run")
    ),
    tool(
      orion_run_bq_query,
      paste(
        "Execute a BigQuery SQL query and return results.",
        "Always call estimate_query_cost first.",
        "Never use SELECT * — name only the columns needed."
      ),
      sql = type_string("The BigQuery SQL query to execute")
    )
  )
)
