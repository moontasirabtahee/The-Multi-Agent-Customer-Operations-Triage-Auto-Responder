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
├── Read.md                     # Master Repository Presentation & Index (This File)
├── setup_project.bat           # Windows batch script for automated venv & dependency setup
├── setup_project.sh            # Unix shell script for automated venv & dependency setup
└── run_tunnel.bat              # Cloudflare reverse tunnel launcher
```

---

## ⚙️ Project Quickstart & Dependency Installation

To easily spin up the virtual environment (`.venv`) and install all required python libraries, simply run the setup script tailored for your platform from the repository root:

*   **Windows**:
    ```bash
    setup_project.bat
    ```
*   **Linux/macOS**:
    ```bash
    chmod +x setup_project.sh
    ./setup_project.sh
    ```

This script will automatically initialize the virtual environment, upgrade pip, install dependencies, and create your local `backend/.env` file from the template.

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

---

## ⚙️ Setting Up n8n Workflow

The `n8n/CustomerOpsTriageEngine.json` file is prepared to house the exported n8n workflow canvas. Once the orchestration workflow is set up, export the JSON from n8n and save it into this file to maintain migrations and version control.

