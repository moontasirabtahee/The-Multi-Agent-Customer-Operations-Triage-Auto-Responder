# The Multi-Agent Customer Operations Triage & Auto-Responder

An enterprise-grade, hybrid-deployed customer support automation engine. The system automates email ingestion, performs multi-agent ticket classification/risk assessment, queries a local secure RAG (Retrieval-Augmented Generation) knowledge base, and incorporates a Slack-based Human-in-the-Loop (HITL) review process before final email dispatch.

---

## 🛠️ Hybrid System Architecture Overview

The project is structured around a decoupled **Hybrid Infrastructure Strategy**:
1. **Public Cloud VPS (Ingress & Orchestration)**: Runs an internet-facing dockerized **n8n** instance to handle incoming webhooks, route traffic, format Slack interaction cards, and manage human approval callbacks.
2. **Private Local Workstation (Heavy Computing)**: Hosts a secure **Django Core API**, **LlamaIndex**, and **pgvector** database, with local LLM inference running on **Ollama** (`gemma2:9b`). This keeps sensitive enterprise data private and eliminates API dependency costs.

---

## 📅 Project Implementation Phases

This project is organized into four technical implementation phases. Click the links below to view the detailed architecture specifications for each phase:

* **[Phase 1: Hybrid Infrastructure Setup](Documents/Phase%201.md)**
  * Details the network topology, cloud VPS deployment with Docker Compose, encrypted Cloudflare reverse tunnels, and core JSON data contracts.
* **[Phase 2: Multi-Agent Routing Engine](Documents/Phase%202.md)**
  * Details the n8n canvas workspace schema, prompt configurations, classification rules (Category, Urgency, Sentiment), and risk filter parameters.
* **[Phase 3: Production-Grade RAG Engine](Documents/Phase%203.md)**
  * Details the local LlamaIndex ingestion pipeline, pgvector database layout, Django API endpoints, and strict system guardrails to prevent hallucinations.
* **[Phase 4: Governance Layer (Slack HITL Integration)](Documents/Phase%204.md)**
  * Details the Slack App workspace configuration, Block Kit interactive message UI, and asynchronous webhook handshakes for human approval.

---

## 📁 Repository Directory Structure

```plaintext
/The Multi-Agent Customer Operations Triage & Auto-Responder
│
├── /Documents
│   ├── Phase 1.md              # Ingress Orchestration & Network Setup
│   ├── Phase 2.md              # n8n Routing & Agent Prompts
│   ├── Phase 3.md              # Django & LlamaIndex RAG Engine
│   └── Phase 4.md              # Slack HITL Governance Layer
│
├── /backend
│   ├── /backend                # Django configuration & settings
│   ├── /triage_api             # API endpoints, DB seeding, LlamaIndex configuration
│   ├── .env.example            # Environment template file
│   └── manage.py
│
├── /n8n
│   └── CustomerOpsTriageEngine.json # Exported n8n workflow canvas configuration JSON
│
├── /knowledge_base             # Source documents ingested into the RAG vector store
│   ├── billing_faq.txt         # Sample enterprise policy article
│   └── ...                     # account, security, API, troubleshooting samples
│
├── /logs                       # Run logs & smoke-test result artifacts (bootstrap output)
│
├── README.md                   # Master Repository Presentation & Index (This File)
├── requirements.txt            # Pinned Python dependencies
├── bootstrap.ps1               # One-command fresh-PC bring-up (venv, DB, seed, run, smoke test)
├── bootstrap.bat               # Double-clickable wrapper for bootstrap.ps1
├── setup_project.bat           # (Legacy) Windows venv & dependency-only setup
├── setup_project.sh            # (Legacy) Unix venv & dependency-only setup
├── run_tunnel.bat              # Cloudflare reverse tunnel launcher (Django API)
└── run_tunnel_ollama.bat       # Cloudflare reverse tunnel launcher (Ollama LLM)
```

---

## ⚙️ Quickstart on a Fresh PC (One Command)

> **Portfolio note:** This project is a demonstration system — it is **not meant to run 24/7**. The intended flow is: bring the whole local pipeline up on demand with a single command, let it run a smoke test that proves the RAG engine works, and commit the generated result log in `logs/` as evidence. Bring it up again live only when you want to drive the n8n orchestrator or a Cloudflare tunnel.

### Prerequisites you install yourself (once)
The bootstrap script provisions *everything else*, but these three are your responsibility:

1. **Python 3.10+**
2. **Docker Desktop** (used to run the pgvector PostgreSQL database — running, no manual config needed)
3. **Ollama** + the two models. Bootstrap **checks** for these but never installs them:
   ```bash
   ollama serve
   ollama pull llama3.2          # or any chat model; set it in backend/.env
   ollama pull nomic-embed-text  # embedding model (must stay 768-dim)
   ```

### Run it
From the repository root:

```powershell
# Windows — sets up venv, deps, .env + SECRET_KEY, pgvector container,
# migrations, seeds the knowledge base, then runs a smoke test and writes
# logs/pipeline_result_<timestamp>.log
powershell -ExecutionPolicy Bypass -File .\bootstrap.ps1
#   ...or just double-click bootstrap.bat
```

Useful flags:

| Command | What it does |
| :--- | :--- |
| `.\bootstrap.ps1` | Full setup + smoke test, then stops Django (produces the result log) |
| `.\bootstrap.ps1 -Serve -Port 8520` | Full setup, then **leaves Django running** on port 8520 for live use / tunneling |
| `.\bootstrap.ps1 -Reseed` | Re-embed the knowledge base even if the vector store is already populated |

A successful `logs/pipeline_result_*.log` shows an in-KB query answered from the knowledge base and an out-of-KB query correctly returning `ESCALATE_TO_HUMAN`.

> The legacy `setup_project.bat` / `setup_project.sh` scripts still exist but only create the venv and install dependencies — `bootstrap.ps1` supersedes them for a full bring-up.

---

## 🔑 Configurable Environment Variables

The local RAG service is fully parameterized. To ship the project to your GPU-enabled PC, update the following key variables in `backend/.env`:

| Variable Name | Description | Default Value |
| :--- | :--- | :--- |
| `SECRET_KEY` | Django project secret authorization token | `django-insecure-...` |
| `ALLOWED_HOSTS` | Safe server hosts (include your Cloudflare tunnel domain here) | `localhost,127.0.0.1` |
| `DB_NAME` | PostgreSQL database name | `customer_ops` |
| `DB_USER` | PostgreSQL user account | `postgres` |
| `DB_PASSWORD` | PostgreSQL user account password | `local_secure_password123` |
| `DB_HOST` | Database server endpoint | `localhost` |
| `DB_PORT` | Database server connection port | `5432` |
| `OLLAMA_HOST` | Ollama model server URL | `http://localhost:11434` |
| `OLLAMA_LLM_MODEL` | Ollama LLM model tag | `<OLLAMA_LLM_MODEL_NAME_HERE>` |
| `OLLAMA_EMBED_MODEL` | Ollama Text Embedding model tag | `<OLLAMA_EMBED_MODEL_NAME_HERE>` |
| `SLACK_BOT_TOKEN` | Slack app bot integration token | `xoxb-...` |
| `SLACK_APP_ID` | Slack application registration ID | `A0BGPR64K2M` |

> **Note:** The Slack values are consumed by the **n8n orchestrator** (the Governance Layer lives on the VPS), not by the Django backend. They are included in `backend/.env.example` for convenience, but set `SLACK_BOT_TOKEN` in your **n8n instance environment** for the `Post Draft to Slack` node to authenticate. See the *Setting Up n8n Workflow* section below.

---

## ⚙️ Setting Up n8n Workflow

The `n8n/CustomerOpsTriageEngine.json` file contains the full exported orchestration canvas. Import it into your n8n instance (**Workflows → Import from File**), then reconnect credentials for your environment. The workflow implements all four phases end to end:

* **Ingress & routing:** `Webhook` → `AI Agent` (Classifier) → `AI Agent1` (Risk Assessor) → `Switch`.
* **RAG branch (High Confidence):** `HTTP Request` (Django RAG endpoint) → `Build Slack Card` → `Post Draft to Slack`.
* **Escalation branch (Low Confidence / Risk):** `Create an issue` (Jira).
* **Slack HITL callback (independent trigger):** `Slack Interactivity` webhook → `Parse Interaction` → `Route Approval` → `Dispatch Customer Email` / `Update Card - Approved` / `Update Card - Escalated`.

Before running the Slack governance layer, configure these in the **n8n instance** (they are consumed by n8n on the VPS, not by Django):

| Setting | Where | Purpose |
| :--- | :--- | :--- |
| `SLACK_BOT_TOKEN` | n8n environment variable | Bearer auth for `chat.postMessage` in the `Post Draft to Slack` node |
| SMTP credential | n8n **Credentials** | Used by the `Dispatch Customer Email` node to send the approved reply |
| RAG endpoint URL | `HTTP Request` node | Point it at your Cloudflare tunnel URL for the local Django API |
| Slack Interactivity Request URL | Slack App dashboard | Set to `https://<your-n8n-host>/webhook/slack-interactive` |

After editing the workflow in n8n, re-export the JSON back into this file to keep it under version control.

> 📋 **See [`N8N_CONFIG.md`](N8N_CONFIG.md)** for the exact node-by-node values (tunnel URLs, model, endpoints, channel, credentials, and Slack app setup) to plug into the imported workflow.

## 📚 Knowledge Base

The `knowledge_base/` folder holds the plain-text source documents that LlamaIndex ingests into the pgvector store. Sample enterprise support content is included (billing, account management, security & privacy, API & integrations, troubleshooting) so the RAG engine returns meaningful answers out of the box. Drop additional `.txt` documents here and re-run the seeder to index them:

```bash
.venv/Scripts/python backend/triage_api/seed_db.py   # Windows
.venv/bin/python backend/triage_api/seed_db.py        # Linux/macOS
```

