# 🕵️‍♂️ Elastic AI Financial Crime Investigator # elastic-fincrime-agent
Agent AI-powered Financial Crime Investigator built with Elastic Agent Builder. Uses Agentic RAG to orchestrate AML, Sanctions, and Entity Resolution workflows across distributed datasets.
This repository contains the datasets, prompts, and configuration logic to build an **Agentic RAG** solution for Anti-Money Laundering (AML) and Financial Fraud detection using **Elastic Agent Builder**.

## 🚀 Overview

Traditional rule-based systems generate 95%+ False Positives. This project demonstrates how an AI Agent can orchestrate **4 specialized tools** to:
1.  **Reduce False Positives:** By cross-referencing alerts with External News (e.g., verifying a source of wealth).
2.  **Detect Hidden Risks:** By using Semantic Search on unstructured transaction notes (e.g., Sanctions evasion).
3.  **Unify Identities:** By performing Entity Resolution across global client databases (Single Client View).

## 📂 Project Structure

The repository is organized into four main directories to separate data, agent logic, tool configuration, and documentation:

### `data/`
Contains the source datasets (NDJSON format) required to populate the Elasticsearch indices. These files are the foundation for all demo scenarios (e.g., the "Baker" case, the "Volkov" cluster).
* `clients.ndjson` → Index: `global-clients`
* `transactions.ndjson` → Index: `transactions`
* `policies.ndjson` → Index: `internal-policies`
* `news.ndjson` → Index: `external-news`

### `prompts/`
Contains the **System Prompts** and **Scenario Scripts** that define the "brain" and behavior of the AI Agents.
* `system_prompt.md`: The system instructions for the **Financial Crime Investigator** (Generalist).
* `identity_agent.md`: The system instructions for the **Global Identity Specialist** (SCV).
* `demo_scenarios.md`: The exact prompts to copy-paste during the live demo.

### `tools/`
Contains the specific **Tool Definitions** (JSON configuration) required to set up the tools within Elastic Agent Builder.
* Includes the specific parameters and descriptions for tools like `search_global_client_database`, `scan_adverse_media`, etc.

### `presentation/`
Contains the **Slide Deck** (PDF/PPTX) used to present the use case, architecture, and business value of this solution.
* Ideal for explaining the concept to stakeholders before showing the technical implementation.

## 📂 Dataset Structure (Indices)

The solution relies on 4 Elasticsearch indices. Source files are located in the `/data` folder:

| Index Name | File Source | Description | Search Tech |
| :--- | :--- | :--- | :--- |
| `global-clients` | `data/clients.ndjson` | KYC profiles across EMEA, AMER, APJ. | Hybrid Search |
| `transactions` | `data/transactions.ndjson` | Transaction logs with unstructured notes. | Hybrid Search |
| `internal-policies` | `data/policies.ndjson` | Compliance PDFs and Rulebooks. | Hybrid Search |
| `external-news` | `data/news.ndjson` | OSINT, Adverse Media, and Leaks. | Hybrid Search |

## 🤖 Agent Configuration

This repository supports the deployment of **two distinct Agent personas**. The configuration files and system prompts for each are located in the `/prompts` directory.

### 1. The Financial Crime Investigator (Generalist)
* **Role:** The main agent for the full demo. Orchestrates all data sources to detect complex crimes (AML, Sanctions, Fraud).
* **Setup File:** Use `prompts/financial-crime-agent` to configure the system prompt and instructions.
* **Required Tools:**
    * `search_global_client_database`
    * `analyze_transaction_patterns`
    * `consult_compliance_handbook`
    * `scan_adverse_media`

### 2. The Global Identity Specialist (Specialist)
* **Role:** A dedicated sub-agent focused solely on cleaning data, finding hidden duplicate identities (Single Client View), and detecting Regulatory Arbitrage.
* **Setup File:** Use `prompts/identity_agent` to configure the system prompt and instructions.
* **Required Tools:**
    * `search_global_client_database` (Primary)

### Tools Definition
Create 4 tools in Elastic Agent Builder mapped to the indices above:

* **Tool:** `search_global_client_database` (Index: `global-clients`)
* **Tool:** `analyze_transaction_patterns` (Index: `transactions`)
* **Tool:** `consult_compliance_handbook` (Index: `internal-policies`)
* **Tool:** `scan_adverse_media` (Index: `external-news`)

## 🎬 Demo Scenarios

Detailed step-by-step scripts, prompts, and narratives for the live demonstration are available in **[SCENARIOS]**.

The demo follows a **"Top-Down" Investigation Workflow**, designed to simulate a real-world Chief Risk Officer (CRO) experience:

1.  **🌍 Phase 1: General Discovery (The Morning Briefing)**
    * *Goal:* Proactively scan the entire dataset to identify top threats without knowing the targets beforehand.
    * *Outcome:* The AI autonomously identifies 3 critical cases.

2.  **🔍 Phase 2: Deep Dive Investigations**
    * **Case A (Sanctions):** Detecting hidden risks in transaction notes (*Eastern Logistics*).
    * **Case B (Efficiency):** Automating False Positive reduction via News (*Luca Moretti*).
    * **Case C (Entity Resolution):** Uncovering hidden networks and Regulatory Arbitrage (*Volkov Cluster*).

*Refer to the `SCENARIOS.md` file for the exact prompts to copy-paste during the demo.*

## Automated Bootstrap 

This repository now includes a shell-based bootstrap flow that provisions:
- Elasticsearch indices and mappings
- Dataset ingest from `data/*.ndjson`
- Agent Builder tools
- Agent Builder agents

The bootstrap is idempotent with safe upsert behavior:
- Indices are created only if missing
- Data is ingested only when the target index is empty
- Tools and agents are created or updated

### Prerequisites

- `bash`
- `curl`
- `jq`

### 1) Configure environment variables

Copy the template and fill in your values:

```bash
cp .env.example .env
```

Set the following in `.env`:
- `ELASTICSEARCH_URL`: Elasticsearch endpoint
- `KIBANA_URL`: Kibana endpoint
- `API_KEY`: shared API key used for both Elasticsearch and Kibana APIs
- `KIBANA_SPACE_ID` (optional): if unset, scripts use the default space

### 2) Run everything in one command

```bash
bash scripts/init/all.sh
```

### 3) Run steps individually (optional)

```bash
bash scripts/init/data.sh
bash scripts/init/tools.sh
bash scripts/init/agents.sh
```

### Index mappings

Mappings are defined in:
- `mappings/global-clients.json`
- `mappings/transactions.json`
- `mappings/internal-policies.json`
- `mappings/external-news.json`
