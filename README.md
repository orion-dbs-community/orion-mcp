# ORION-DBs MCP Server

Connects Claude Desktop to the [ORION-DBs](https://orion-dbs.community/) collection on Google BigQuery, so you can explore open research information datasets (OpenAlex, Crossref, ORCID, DataCite, and more) by asking questions in plain language.

## What it does

Claude can list available datasets, inspect table schemas, estimate query costs, and run SQL queries — all without you writing a single line of SQL.

## Prerequisites

- [Docker Desktop](https://www.docker.com/products/docker-desktop/) installed and running
- [Claude Desktop](https://claude.ai/download) installed
- A Google account with access to BigQuery (a free [Google Cloud account](https://cloud.google.com/free) is sufficient — you get 1 TB of free queries per month)
- [Google Cloud CLI (`gcloud`)](https://cloud.google.com/sdk/docs/install) installed

## Installation

### 1. Authenticate with Google Cloud

```bash
gcloud auth application-default login
```

This opens a browser window. Log in with the Google account that has BigQuery access. You only need to do this once (credentials are stored in `~/.config/gcloud/`).

### 2. Find your BigQuery billing project

You need a GCP project ID to bill queries against (queries within the free tier cost nothing). Find it in the [Google Cloud Console](https://console.cloud.google.com/) — it looks like `my-project-123456`.

### 3. Build the Docker image

```bash
git clone <this-repo>
cd mcp_docker_playground
docker build -t mcp_docker_playground_mcp .
```

This takes a few minutes the first time while R packages are installed.

### 4. Add the server to Claude Desktop

Open `~/Library/Application Support/Claude/claude_desktop_config.json` (Mac) and add the `orion-dbs` entry inside `mcpServers`:

```json
{
  "mcpServers": {
    "orion-dbs": {
      "command": "/usr/local/bin/docker",
      "args": [
        "run", "--rm", "-i",
        "-v", "/Users/YOUR_USERNAME/.config/gcloud:/root/.config/gcloud:ro",
        "-e", "SCHEMA_DIR=/data",
        "-e", "BQ_BILLING_PROJECT=YOUR_PROJECT_ID",
        "mcp_docker_playground_mcp",
        "Rscript", "/mcp_server.R"
      ]
    }
  }
}
```

Replace `YOUR_USERNAME` with your macOS username and `YOUR_PROJECT_ID` with your GCP project ID.

### 5. Restart Claude Desktop

Quit and reopen Claude Desktop. You should see **orion-dbs** listed under Settings > Developer > MCP Servers.

## Usage

Just ask Claude naturally:

- *"What datasets are available in ORION-DBs?"*
- *"Show me the schema for the Crossref works table."*
- *"How many open access articles were published in 2023 per year, broken down by OA type?"*

Claude will call the tools in the right order: browse datasets, inspect schemas, estimate query cost, then run the query.

## Cost and safety

BigQuery bills by bytes scanned (not rows returned). Two safeguards are built in:

- **Dry-run before every query** — Claude always calls `orion_estimate_query_cost` first and reports how many GB the query will scan.
- **No `SELECT *`** — queries that select all columns are blocked. Claude names only the columns it needs, which is the main lever for controlling cost.

The [BigQuery sandbox](https://cloud.google.com/bigquery/docs/sandbox) gives every account 1 TB of free queries per month, which is more than enough for exploration.

## Rebuilding after updates

If you pull new changes, rebuild the image before restarting Claude Desktop:

```bash
docker build -t mcp_docker_playground_mcp .
```
