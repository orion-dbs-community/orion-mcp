# ORION-DBs MCP Server

Connects Claude Desktop to the [ORION-DBs](https://orion-dbs.community/) collection on Google BigQuery, so you can explore open research information datasets (OpenAlex, Crossref, ORCID, DataCite, and more) by asking questions in plain language.

## What it does

Claude can list datasets, inspect table schemas, estimate query costs, and run SQL queries.

| Function | Description | GCP Account Required |
|----------|-------------|---------------------|
| `orion_list_datasets` | List all available datasets in ORION-DBs | ❌ No |
| `orion_list_tables` | Display all tables in a specific dataset | ❌ No |
| `orion_get_db_schema` | Inspect the full schema of a table | ❌ No |
| `orion_estimate_query_cost` | Estimate bytes scanned (and cost) before running a query | ✅ Yes |
| `orion_run_bq_query` | Execute a SQL query against BigQuery | ✅ Yes |

## Security

**Does this give Claude access to my files?**
No. The MCP server runs in an isolated Docker container with no access to your filesystem. The only thing shared with the container is your Google Cloud credentials directory (`~/.config/gcloud`), mounted read-only so the server can authenticate to BigQuery.

**Can Claude read my private BigQuery datasets?**
Only if you tell it their names — Claude has no way to enumerate your private datasets. Accessing a private dataset requires both the `bigquery.readonly` OAuth scope *and* the `roles/bigquery.dataViewer` IAM role on that specific dataset. For your own GCP projects, your account likely already has that role — so if Claude were given a private dataset name it could query it. The practical protection is that Claude only knows what you tell it.

**Can it run up a big BigQuery bill without me knowing?**
No. Every query is preceded by a free dry-run that estimates the cost. Claude is instructed to present the estimate and wait for your explicit confirmation before executing. `SELECT *` queries are blocked entirely.

**Do query results leave my machine?**
Results appear in your Claude conversation — the same as anything else you discuss with Claude. They are not sent anywhere else.

## Installation

**Prerequisites:** [Docker Desktop](https://www.docker.com/products/docker-desktop/), [Claude Desktop](https://claude.ai/download), [gcloud CLI](https://cloud.google.com/sdk/docs/install)

### 1. Authenticate with Google Cloud

```bash
gcloud auth application-default login
```

This opens a browser window and stores credentials in `~/.config/gcloud/`. You only need to do this once. When the MCP server starts, it requests only a `bigquery.readonly` access token — the narrowest scope needed to run queries.

### 2. Pull the Docker image

```bash
docker pull ghcr.io/orion-dbs-community/orion-mcp:latest
```

### 3. Add the server to Claude Desktop

Open your Claude Desktop config file in a text editor:

- **macOS:** `~/Library/Application Support/Claude/claude_desktop_config.json`
  > `Library` is a hidden folder. Open it from Terminal with:
  > ```bash
  > open ~/Library/Application\ Support/Claude/claude_desktop_config.json
  > ```
  > Or in Finder: **Go → Go to Folder** (`⇧⌘G`) and paste `~/Library/Application Support/Claude/`
- **Linux:** `~/.config/Claude/claude_desktop_config.json`

Add the `orion-dbs` entry inside `mcpServers`:

```json
{
  "mcpServers": {
    "orion-dbs": {
      "command": "docker",
      "args": [
        "run", "--rm", "-i",
        "-v", "/Users/YOUR_USERNAME/.config/gcloud:/root/.config/gcloud:ro",
        "-e", "BQ_BILLING_PROJECT=YOUR_PROJECT_ID",
        "ghcr.io/orion-dbs-community/orion-mcp:latest"
      ]
    }
  }
}
```

Replace:
- `YOUR_USERNAME` — your macOS/Linux username (on Linux use `/home/YOUR_USERNAME/...`)
- `YOUR_PROJECT_ID` — your GCP project ID, e.g. `my-project-123456`. Find it in the [Google Cloud Console](https://console.cloud.google.com/) by clicking the project selector in the top bar. 

> Schema browsing (`orion_list_datasets`, `orion_list_tables`, `orion_get_db_schema`) works without a billing project. You can omit the `BQ_BILLING_PROJECT` line entirely if you only want to explore schemas.

#### Accessing exported files

When you ask Claude to export query results, files are written to `/data/exports` **inside the container**. To access them on your machine, add a volume mount:

```json
{
  "mcpServers": {
    "orion-dbs": {
      "command": "docker",
      "args": [
        "run", "--rm", "-i",
        "-v", "/Users/YOUR_USERNAME/.config/gcloud:/root/.config/gcloud:ro",
        "-v", "/Users/YOUR_USERNAME/Downloads/orion-exports:/data/exports",
        "-e", "BQ_BILLING_PROJECT=YOUR_PROJECT_ID",
        "ghcr.io/orion-dbs-community/orion-mcp:latest"
      ]
    }
  }
}
```

The second `-v` line mounts `~/Downloads/orion-exports` on your machine to `/data/exports` in the container. Exported CSVs and JSON files will appear there. You can use any directory you like — just create it first (`mkdir ~/Downloads/orion-exports`).

To change the in-container export path, set the `EXPORT_DIR` environment variable (e.g. `-e EXPORT_DIR=/tmp/exports`).

### 4. Restart Claude Desktop

Quit and reopen Claude Desktop. You should see **orion-dbs** listed under Settings → Developer → MCP Servers.

## Usage

Ask Claude in plain language:

**No Google Cloud account required**
- *"What datasets are available in ORION-DBs?"*
- *"Show me the schema for the Crossref works table."*
- *"Which versions of OpenAlex are available and how do the schemas compare?"*

**Google Cloud account required**
- *"How many publications were published by University of Göttingen researchers between 2021 and 2025 in journals?"*
- *"How many open access articles were published in 2023, broken down by OA type?"*

## Cost and safety

BigQuery bills by bytes scanned (not rows returned). Two safeguards are built in:

- **Dry-run before every query** — Claude always calls `orion_estimate_query_cost` first and reports how many GB the query will scan. It will not proceed without your explicit confirmation.
- **No `SELECT *`** — queries that select all columns are blocked. Naming only the columns needed is the main lever for controlling cost.

The [BigQuery sandbox](https://cloud.google.com/bigquery/docs/sandbox) gives every account 1 TB of free queries per month.

## How authentication works

The MCP server runs in a Docker container and authenticates via Application Default Credentials (ADC): your local `gcloud` credentials are mounted read-only into the container. No service account keys are created or shared.

## Contributing / local development

To build the image locally instead of pulling from the registry:

```bash
git clone https://github.com/orion-dbs-community/orion-mcp
cd orion-mcp
docker build -t orion-mcp_mcp .
```

Then use `orion-mcp_mcp` as the image name in your Claude Desktop config.
