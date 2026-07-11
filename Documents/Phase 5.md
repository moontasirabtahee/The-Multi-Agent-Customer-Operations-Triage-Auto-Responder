# Architecture Specification: Closure, Optimization, & Presentation

## Phase 5: Complete Workflow Termination and Safety Fallbacks

This document outlines the final phase of the customer operations automation pipeline, defining how the Slack-based Human-in-the-Loop (HITL) approval loop terminates, how automated outbound emails are dispatched, and how safety-critical RAG exception paths are handled.

---

## 1. Phase 5 Complete Workflow Termination Topology

The wireframe below details how the Slack interactive action webhook is parsed and routes down the success path (dispatched email) or the rejection path (Jira escalation ticket).

```plaintext
=======================================================================================================================
                                        PHASE 5 COMPLETE WORKFLOW TERMINATION
=======================================================================================================================

     [ Slack Interaction Webhook ] Path: /webhook/slack-interactive (Outbound Cloud Event)
                  │
                  ▼
     ┌────────────────────────┐
     │  JavaScript Parser     │ (Extracts action_id, recipient, and validated draft)
     └────────────┬───────────┘
                  │
         ┌────────┴──────────────┐
         │                       │
         ▼ [ action_id ===       ▼ [ action_id ===
      "approve_triage_send" ]  "reject_triage_escalate" ]
         │                       │
         ▼                       ▼
     ┌────────────────────────┐ ┌────────────────────────┐
     │   Gmail / SMTP Node    │ │   Jira Software Node   │
     │  (Dispatches Email)    │ │ (Creates High-Priority │
     └────────────┬───────────┘ │  Manual Review Ticket) │
                  │             └────────────────────────┘
                  ▼
         [ SYSTEM SUCCESS ]
```

---

## 2. Inbound & Outbound Ingress Mapping Specifications

### 2.1 Outbound Email Dispatch (Gmail / SMTP Node)
When an agent reviews and clicks the green **Approve & Send** button inside the Slack team channel:
* **Webhook Event Capture:** The `Slack Interactivity` webhook node on the VPS catches the interactive action payload.
* **JavaScript Parsing:** The `Parse Interaction` node extracts the following values:
  * `validatedDraftText`: The human-approved and edited draft.
  * `customer_email`: The recipient customer's email.
  * `user`: The name of the Slack reviewer who authorized the send.
* **SMTP Delivery:** The `Dispatch Customer Email` node dispatches the email using the following parameters:
  * **To:** `{{ $('Webhook').item.json.body.sender_email }}` (re-anchoring back to the initial customer ticket).
  * **Subject:** `Re: {{ $('Webhook').item.json.body.subject || 'Your Support Request' }}`
  * **Body:** `{{ $json.validatedDraftText }}`

---

## 3. Automated RAG Exception Fallback Routing

To protect against hallucinations and ensure high-risk or low-confidence queries are reviewed by human engineers, the RAG API returns the token `ESCALATE_TO_HUMAN` when no relevant matches exist in the pgvector database.

### 3.1 The "Check RAG Fallback" Gateway
An If node is positioned immediately after the Django HTTP Request node:
* **Evaluated Expression:** `{{ $json.generated_draft }}`
* **Condition Rule:** `String EQUALS ESCALATE_TO_HUMAN`
* **True Branch:** Routes to the **Jira** node to instantly create a manual review issue. The ticket's description is appended with:
  > `"AI safety fallback triggered: insufficient internal documentation found to safely auto-respond."`
* **False Branch:** Routes to the **Build Slack Card** block to initiate the standard human-in-the-loop review.

---

## 4. Operational Diagnostics Checklist

Before declaring the system production-ready, verify the end-to-end integration flow passes these verification checks:

| Target Component | Diagnostic Test Case | Expected Outcome |
| :--- | :--- | :--- |
| **Outbound SMTP Node** | Trigger Google Apps Script with a valid email query → Click **Approve & Send** in Slack | Customer receives the formatted support reply; Slack card updates to "Approved". |
| **RAG Fallback Node** | Send query outside pgvector database scope (e.g. asking for unrelated policies) | n8n routes directly to Jira; new issue appears with "AI Safety Fallback: Insufficient Docs" title. |
| **State Reset** | Run script on already-read threads | Execution logs confirm 0 threads found, avoiding duplicate email responses. |
