# Architecture Specification: Hybrid Infrastructure Setup

## Phase 1: Ingress Orchestration, Network Tunneling, and System Interface

This document defines the deployment infrastructure, data synchronization flow, and runtime contracts for the **Multi-Agent Customer Operations Triage & Auto-Responder System**.  
The system implements a decoupled hybrid architecture: anchoring the event-driven entry point (n8n Webhook Listener) on an internet-facing cloud VPS to guarantee high availability, while keeping the core resource-heavy components (Django Core and Ollama LLM Inference) on a private local network to control operational costs and protect sensitive corporate data.

## 1. System Topology Wireframe (Network Layout)

The wireframe below highlights how data crosses network boundaries securely using an encrypted reverse tunnel, eliminating the need to expose local development ports to the public internet.  

```plaintext
=======================================================================================================================  
                                      PHASE 1 NETWORK INFRASTRUCTURE TOPOLOGY  
=======================================================================================================================

       [ CUSTOMER INBOUND ]  
                │  
                │ (SMTP / HTTP Inbound Email Webhook)  
                ▼  
┌────────────────────────────────────────────────────────┐  
│                      CLOUD VPS                         │  
│                                                        │  
│  ┌─────────────────────────┐                           │  
│  │    n8n Orchestrator     │                           │  
│  │ (Dockerized Event Node) │                           │  
│  └──────────┬──────────────┘                           │  
└─────────────┼──────────────────────────────────────────┘  
              │                               ▲  
              │ (Secure Outbound Tunnel)      │ (Interactive Callback Webhook)  
              │ https://*.trycloudflare.com   │  
              ▼                               │  
┌─────────────────────────────────────────────┼──────────┐  
│              LOCAL WORKSTATION              │          │  
│                                             │          │  
│  ┌───────────────────────┐   ┌──────────────┴───────┐  │  
│  │    Ollama API Engine  │   │ Django Core Engine   │  │  
│  │ (Local Inference Port)│   │  (REST API Endpoint) │  │  
│  │      [11434]          │   │       [8000]         │  │  
│  └───────────────────────┘   └──────────────┬───────┘  │  
│                                             ▼          │  
│                              ┌──────────────────────┐  │  
│                              │   PostgreSQL DB      │  │  
│                              │  (pgvector Store)    │  │  
│                              └──────────────────────┘  │  
└────────────────────────────────────────────────────────┘  
                                              │  
                                              │ (Outbound OAuth Token)  
                                              ▼  
                               ┌──────────────────────┐  
                               │   SLACK CLOUD APP    │  
                               │  (Human-in-the-Loop  │  
                               │   Approval Channel)  │  
                               └──────────────────────┘
```

## 2. The Core Data Contract (Systemic Interface)

To ensure decoupled, microservice-style communication between the **n8n Routing Agents**, the **Local Inference Engine**, and the **Django RAG Backend**, all structured payloads must adhere strictly to this JSON validation schema.  

```json
{  
  "$schema": "https://json-schema.org/draft/2020-12/schema",  
  "title": "CustomerTicketTriageSchema",  
  "type": "object",  
  "required": ["ticket_metadata", "classification", "assessment"],  
  "properties": {  
    "ticket_metadata": {  
      "type": "object",  
      "required": ["sender_email", "received_at"],  
      "properties": {  
        "sender_email": { "type": "string", "format": "email" },  
        "received_at": { "type": "string", "format": "date-time" }  
      }  
    },  
    "classification": {  
      "type": "object",  
      "required": ["category", "urgency", "sentiment"],  
      "properties": {  
        "category": { "type": "string", "enum": ["BILLING", "BUG", "FEATURE_REQUEST", "GENERAL_INQUIRY"] },  
        "urgency": { "type": "string", "enum": ["LOW", "MEDIUM", "HIGH", "CRITICAL"] },  
        "sentiment": { "type": "string", "enum": ["POSITIVE", "NEUTRAL", "FRUSTRATED", "ANGRY"] }  
      }  
    },  
    "assessment": {  
      "type": "object",  
      "required": ["confidence_score", "can_auto_respond", "escalation_reason"],  
      "properties": {  
        "confidence_score": { "type": "number", "minimum": 1.0, "maximum": 10.0 },  
        "can_auto_respond": { "type": "boolean" },  
        "escalation_reason": { "type": ["string", "null"] }  
      }  
    }  
  }  
}
```

## 3. Workstation Directory Structure

The repository is cleanly divided by operational responsibilities, separating orchestration workflows from core application logic.  

```plaintext
/customer-ops-triage  
│  
├── /backend            # Django REST application & LlamaIndex configurations  
├── /n8n                # Production n8n JSON pipeline migrations  
├── /knowledge_base     # Source documents ingested into the RAG vector store  
├── /Documents          # Phase-by-phase architecture specifications  
├── README.md           # Master System Architecture Documentation  
└── requirements.txt    # Pinned Python dependencies
```

> **VPS-only asset:** The `docker-compose.yml` shown in section 4 below is deployed directly onto the public cloud VPS to launch the dockerized n8n orchestrator; it is not part of this local-workstation repository.

## 4. VPS Orchestration Deployment Configuration

The following highly optimized docker-compose.yml file is configured for deployment on the public Linux VPS. It isolation-binds the n8n application engine to an explicit Docker bridge network.  

```yaml
version: '3.8'

networks:  
  triage-network:  
    driver: bridge

services:  
  n8n:  
    image: docker.n8n.io/n8nio/n8n:latest  
    container_name: triage_n8n  
    restart: always  
    ports:  
      - "5678:5678"  
    environment:  
      - N8N_HOST=your-vps-ip-or-domain  
      - N8N_PORT=5678  
      - N8N_PROTOCOL=http  
      - GENERIC_TIMEZONE=UTC  
    volumes:  
      - n8n_data:/home/node/.n8n  
    networks:  
      - triage-network

volumes:  
  n8n_data:
```

## 5. Security Access Optimization (VPS User Mapping)

To adhere to security best practices and prevent the security flaws associated with running commands blindly under root users, the deployment environment maps the current active shell account directly into Docker's secondary authorization group.  

```bash
# Initialize Docker access group context  
sudo groupadd docker

# Add active deployment user profile to mapping array  
sudo usermod -aG docker $USER

# Force system initialization of updated group settings without restarting active shell session  
newgrp docker
```

## 6. Infrastructure Verification Sign-Off Matrix

Before migrating to Phase 2, the network routing endpoints must successfully pass these manual diagnostic validation steps:

| Target Component | Verification Command | Expected Success Result |
| :---- | :---- | :---- |
| **Local LLM Engine** | `curl http://localhost:11434/api/tags` | JSON array confirming local presence of target model (gemma2:9b or llama3.2) |
| **Reverse Network Tunnel** | Navigate to custom tunnel URL via external browser | Plaintext verification response: "Ollama is running" |
| **Cloud Orchestration Gate** | Access `http://[YOUR-VPS-IP]:5678` | Renders active, authenticated n8n workspace canvas |

---

## 7. Email Ingress via Google Apps Script (Trigger Forwarder)

The system utilizes an event-driven ingress strategy to ingest customer support emails:
* **Gmail Pull Mechanism:** A cloud-based **Google Apps Script** executes on a time-driven trigger (configured to run dynamically every 5-10 minutes, or manually every minute for testing).
* **Ingress Filtering:** The script queries the Gmail inbox using `is:unread label:inbox after:YYYY/MM/DD` to capture only unread emails received on the current date, processing only the single most recent unread thread.
* **Webhook Forwarding:** It compiles the payload (`sender_email`, `text`, and `subject`) and forwards it as a JSON POST request to the n8n Webhook node (`/webhook/triage` or `/webhook-test/triage`).
* **State Management:** Once the webhook returns a successful response code (`2xx`), the script marks the email thread as read in Gmail to prevent duplicate processing.

