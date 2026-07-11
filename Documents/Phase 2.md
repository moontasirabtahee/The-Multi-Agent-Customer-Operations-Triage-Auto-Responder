# Architecture Specification: Multi-Agent Routing Engine

## Phase 2: Orchestration, Context Anchoring, and Deterministic Gating

This document outlines the visual layout, structural JSON schema relationships, prompt configurations, and data verification steps executing within the dockerized n8n service on the cloud VPS.

## 1. Technical Flowchart & Data Boundaries

The architecture handles state and context by splitting data paths. While metadata transitions sequentially through the agent chain, the original unstructured context is preserved via a structural root-anchor extraction.  

```plaintext
=======================================================================================================================  
                                      SYSTEM DATA FLOW AND NETWORK BOUNDARY MATRIX  
=======================================================================================================================

      [ CLIENT INGRESS ]  
              │  
              ▼ (HTTP POST payload)  
  ┌──────────────────────┐  
  │   Webhook Node       │ ◄───[SYSTEM EDGE BOUNDARY (Cloud VPS)]  
  │   Name: "Webhook"    │  
  └──────────┬───────────┘  
              │  
              ├───(Passes raw input string)─────────────────────────────────────────────┐  
              │                                                                         │  
              ▼ (Triggers Agent Loop via Cloudflare Secure Tunnel)                      │  
  ============================================== REVERSE TUNNEL =======================│=======================  
              │                                                                         │  
              ▼                                                                         │  
  ┌────────────────────────────────────────────────────────┐                           │  
  │ AI Agent (Node 1: Classifier)                          │                           │  
  │ - Model: gemma2:9b (Ollama OpenAI Compatible Engine)   │                           │  
  │ - Temperature: 0.0                                     │                           │  
  └──────────────────────────┬─────────────────────────────┘                           │  
                             │                                                         │  
                             ▼ (Emits Structured Category/Urgency/Sentiment JSON)      │  
  ┌────────────────────────────────────────────────────────┐                           │  
  │ AI Agent1 (Node 2: Assessor)                           │                           │  
  │ - Model: gemma2:9b                                     │                           │  
  │ - Context Anchor: {{ $('Webhook').item.json.body.text }}◄──────────────────────────┘  
  │ - Temperature: 0.1                                     │  
  └──────────────────────────┬─────────────────────────────┘  
                             │  
                             ▼ (Emits Structured Confidence/Autonomy JSON)  
  ============================================== REVERSE TUNNEL ===============================================  
                             │  
                             ▼ (Exits Tunnel back to VPS Runtime)  
  ┌────────────────────────────────────────────────────────┐  
  │ Switch Node (Deterministic Evaluation Matrix)          │  
  └──────────────────────────┬─────────────────────────────┘  
                             │  
              ┌──────────────┴──────────────┐  
              │                             │  
    [ TRUE: High Confidence ]     [ FALSE: Low Confidence / Risk ]  
              │                             │  
              ▼                             ▼  
  ┌──────────────────────┐      ┌──────────────────────┐  
  │  HTTP Request Node   │      │   Jira Ticket Node   │  
  │ (To Local Django RAG)│      │ (Human Intervention  │  
  │  Path: /api/v1/triage│      │  Escalation Queue)   │  
  └──────────────────────┘      └──────────────────────┘
```

## 2. Visual Canvas Wireframe (n8n Workspace Schema)

This blueprint represents the layout and sub-node attachment mappings inside your n8n workspace canvas. Note how the structured output parsers mount below the parent agents to tap into the ai_outputParser data execution sockets.  

```plaintext
+-------------------------------------------------------------------------------------------------------------------------+  
| n8n Canvas Workflow: Customer Ops Triage Engine                                                                [Active] |  
+-------------------------------------------------------------------------------------------------------------------------+  
|                                                                                                                         |  
|   +---------------+         +---------------+         +---------------+         +---------------+                       |  
|   |    Webhook    |         |   AI Agent    |         |   AI Agent1   |         |    Switch     |                       |  
|   |               | =======>|  (Classifier) | =======>|   (Assessor)  | =======>|               |                       |  
|   | [Path: triage]|         +-------▲-------+         +-------▲-------+         +-------┬-------+                       |  
|   +---------------+                 ║                         ║                         │                               |  
|                                     ║ (ai_languageModel)      ║ (ai_languageModel)      ├─► [High Confidence Output]    |  
|                             +-------╩-------+         +-------╩-------+         │   └──► HTTP Request Node              |  
|                             │ OpenAI Chat   │         │ OpenAI Chat   │         │                                       |  
|                             │ Model         │         │ Model1        │         └─► [Human Queue / Escalated Output]    |  
|                             +---------------+         +---------------+             └──► Create an issue (Jira)         |  
|                                     ║                         ║                                                         |  
|                                     ║ (ai_outputParser)       ║ (ai_outputParser)                                       |  
|                             +-------╩-------+         +-------╩-------+                                                 |  
|                             │  Structured   │         │  Structured   │                                                 |  
|                             │ Output Parser │         │Output Parser1 │                                                 |  
|                             +---------------+         +---------------+                                                 |  
|                                                                                                                         |  
+-------------------------------------------------------------------------------------------------------------------------+
```

## 3. Core Node Configuration Profiles

### Node Group 1: Categorization & Sentiment Extraction

* **Parent Node:** AI Agent (ID: `148c5146-...`)  
  * **Prompt Type:** Define below  
  * **System Prompt:**  
    > You are an elite Operations Triage Specialist. Your sole responsibility is to analyze unstructured incoming customer communications and extract structured analytical metadata.  
    > Analyze the input text and extract parameters detailing the core topic category, calculated escalation urgency, and baseline consumer emotional state.
* **Language Model Sub-Node:** OpenAI Chat Model (ID: `36331d0a-...`)  
  * **Model Selection:** Expression -> gemma2:9b or llama3.2  
  * **Temperature:** 0.0  
* **Parser Sub-Node:** Structured Output Parser (ID: `b9fbfbfe-...`)  
  * **Property JSON Schema Injection:**  
```json
[  
  { "name": "category", "type": "string", "description": "Must be exactly one of: BILLING, BUG, FEATURE_REQUEST, GENERAL_INQUIRY" },  
  { "name": "urgency", "type": "string", "description": "Must be exactly one of: LOW, MEDIUM, HIGH, CRITICAL" },  
  { "name": "sentiment", "type": "string", "description": "Must be exactly one of: POSITIVE, NEUTRAL, FRUSTRATED, ANGRY" }  
]
```

### Node Group 2: Autonomy Optimization & Risk Filter

* **Parent Node:** AI Agent1 (ID: `9d74a958-...`)  
  * **Prompt Type:** Define below  
  * **Dynamic Input Expression Text Field:** `={{ $('Webhook').item.json.body.text }}`  
  * **System Prompt:**  
    > You are a Risk Assessment Engineer overseeing an autonomous customer support pipeline. Your job is to determine if an incoming ticket can be safely resolved by an automated Retrieval-Augmented Generation (RAG) system, or if it must be routed to a human engineer.
    > 
    > You will evaluate the raw email text alongside the classification metadata provided by the preceding routing agent:  
    > `[Classification Input Metadata]: {{ $json.category }} | {{ $json.urgency }} | {{ $json.sentiment }}`
    > 
    > Rules for Autonomy:  
    > - If Category is BUG, set can_auto_respond to false and confidence_score below 8.0.  
    > - If Urgency is CRITICAL or Sentiment is ANGRY, set can_auto_respond to false.  
    > - If the request asks for specific database updates, credentials, or financial refunds, set can_auto_respond to false.  
    > - General inquiries or standard billing queries have high baseline confidence scores.
* **Language Model Sub-Node:** OpenAI Chat Model1 (ID: `648bf6a1-...`)  
  * **Model Selection:** Expression -> gemma2:9b or llama3.2  
  * **Temperature:** 0.1  
* **Parser Sub-Node:** Structured Output Parser1 (ID: `58c645ef-...`)  
  * **Property JSON Schema Injection:**  
```json
[  
  { "name": "confidence_score", "type": "number", "description": "A floating-point evaluation between 1.0 and 10.0 representing automated accuracy likelihood." },  
  { "name": "can_auto_respond", "type": "boolean", "description": "True if it can be resolved autonomously via internal documentation, false otherwise." },  
  { "name": "escalation_reason", "type": "string", "description": "Text stating the core justification for human handoff if autonomous is false, otherwise null." }  
]
```

## 4. Operational Gatekeeper (The Switch Node)

* **Parent Node:** Switch (ID: `7454d227-...`)  
* **Mode:** Rules-Based Array Evaluation  
* **Branch 1 (Output Key:** High Confidence**):**  
  * Expression Statement: `={{ $json.can_auto_respond === true && $json.confidence_score >= 8 }}`  
  * Route Destination: HTTP Request Node -> Local Django Core API Endpoint.  
* **Branch 2 (Output Key:** Human Queue / Escalated**):**  
  * Expression Statement: `={{ $json.can_auto_respond === false || $json.confidence_score < 8 }}`  
  * Route Destination: Create an issue Node -> Jira Operations Backlog.

## 5. End-to-End Verification Check

To confirm code execution success, trigger the webhook using an integrated REST client (e.g., Postman or curl via terminal):  

```bash
curl -X POST https://your-vps-n8n-url.com/webhook/triage \  
  -H "Content-Type: application/json" \  
  -d '{"text": "I need to know what your official enterprise refund policy is if our server uptime falls below 99.9% this quarter."}'
```

### Expected Execution Log Result

1. AI Agent parses payload and outputs: `category: "BILLING", urgency: "MEDIUM", sentiment: "NEUTRAL"`.  
2. AI Agent1 processes the raw string anchor, matches against the refund rule restriction, and drops the state: `can_auto_respond: false, confidence_score: 5.5`.  
3. Switch intercepts data properties, flags Branch 2 as matching true, and fires the Jira Node execution block while safely keeping the HTTP automated responder branch idle.
