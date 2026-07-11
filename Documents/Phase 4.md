# Architecture Specification: Governance Layer (Slack Human-in-the-Loop Integration)

## Phase 4: Human-in-the-Loop, Block Kit UI, and Asynchronous Webhooks

In an enterprise environment, companies are concerned with letting AI auto-reply to customers blindly. Hallucinations, tone issues, or leaked data can be problematic. That’s why senior engineers design a **Human-in-the-Loop (HITL)** governance framework.  
Instead of sending the response generated in Phase 3 directly to the customer, our n8n orchestrator will catch it, build an interactive card, and push it to an internal corporate Slack channel. A manager can then review it, click an **[Approve & Send]** button, or edit it right inside Slack.

## 1. Phase 4 Architecture & Interaction Lifecycle

This phase requires an **asynchronous webhook handshake**. n8n acts as the permanent listener on your VPS, while Slack acts as the cloud-based interactive UI platform.  

```plaintext
=======================================================================================================================  
                                      PHASE 4 HUMAN-IN-THE-LOOP INTERACTION LOOP  
=======================================================================================================================

    ┌────────────────────────────────────────┐  
    │  Django RAG API returns draft response  │  
    └───────────────────┬────────────────────┘  
                        │  
                        ▼  
    ┌────────────────────────────────────────┐  
    │ n8n Formats Slack Block Kit Payload    │  
    └───────────────────┬────────────────────┘  
                        │  
                        ▼ (HTTP POST Outbound OAuth Token)  
  ══════════════════════╪═══════════════════════════════════════════════════════════════════ CLOUD SAAS BOUNDARY ══════  
                        │  
                        ▼  
    ┌────────────────────────────────────────┐  
    │ Internal Slack Triage Channel          │  
    │ - Displays Email Text & Draft Reply     │  
    │ - Renders [Approve & Send] UI Button   │  
    └───────────────────┬────────────────────┘  
                        │  
                        ▼ (A Live Support Agent reviews text and clicks "Approve")  
    ┌────────────────────────────────────────┐  
    │ Slack Interactivity Endpoint Fires     │  
    └───────────────────┬────────────────────┘  
                        │  
                        ▼ (Inbound Interactive Event Webhook Payload)  
  ══════════════════════╪═══════════════════════════════════════════════════════════════════ CLOUD SAAS BOUNDARY ══════  
                        │  
                        ▼ Path: /webhook/slack-interactive  
    ┌────────────────────────────────────────┐  
    │ n8n Catches Callback & Dispatches Email│  
    │ - Sends final response to customer     │  
    └────────────────────────────────────────┘
```

## 2. Setting Up Your Slack Application Workspace

To connect your VPS orchestrator to Slack, you need to create a custom internal integration.

1. Go to the [Slack API Dashboard](https://api.slack.com/apps) and click **Create New App** -> **From Scratch**.  
2. Name your app `Customer Ops Triage Gatekeeper` and link it to your development Slack workspace.  
3. Under **Features**, navigate to **OAuth & Permissions** and add the following **Bot Token Scopes**:  
   * `chat:write` (Allows n8n to post the draft response messages).  
   * `chat:write.public` (Allows posting into channels without manual invitation).  
4. Click **Install to Workspace** at the top of the page. Copy the generated **Bot User OAuth Token** (starts with `xoxb-`). Save this into your n8n credentials database under **Slack API**.

## 3. UI Design via Slack Block Kit Wireframe

Inside n8n, we will use Slack’s layout framework called **Block Kit** to format the message card. We want the triage agent to see the problem context and the solution context instantly.  
Here is what the message wireframe looks like when it renders inside the support channel:  

```plaintext
+-------------------------------------------------------------------------------------------------------------------+  
| # customer-ops-triage                                                                                             |  
+-------------------------------------------------------------------------------------------------------------------+  
| 📥 **NEW HIGH-CONFIDENCE Triage Draft** |  
|                                                                                                                   |  
| *Customer:* customer@domain.com                                                                                    |  
| *Original Query:* |  
| > "How do I update my billing credit card info before the next billing cycle?"                                    |  
|                                                                                                                   |  
| 🤖 *AI Generated Response:* |  
| ```                                                                                                               |  
| Hi there, you can safely update your payment profile by navigating to Settings -> Billing -> Update Payment. ... |  
| ```                                                                                                               |  
|                                                                                                                   |  
| +------------------+   +----------------+                                                                         |  
| |  Approve & Send  |   |   Escalate /   |                                                                         |  
| |     (Green)      |   |  Reject (Red)  |                                                                         |  
| +------------------+   +----------------+                                                                         |  
+-------------------------------------------------------------------------------------------------------------------+
```

## 4. Implemented n8n Nodes (Outbound Draft Posting)

These nodes are wired directly into `n8n/CustomerOpsTriageEngine.json` on the **High Confidence** branch of the Switch, immediately after the Phase 3 `HTTP Request` node that calls the Django RAG API.

```plaintext
  Switch [High Confidence] ──► HTTP Request (Django RAG) ──► Build Slack Card ──► Post Draft to Slack
```

### Node A1: `Build Slack Card` (Code Node)

Rather than hand-escaping a large Block Kit blob inside a single expression, the payload is assembled in a small JavaScript Code node. It reads the original ticket context from the `Webhook` node and the `generated_draft` returned by the RAG API, then emits a ready-to-send `slackBody` object. The approve button carries a compact JSON `value` (`{ email, draft }`) so the interactivity callback can dispatch the reply without re-querying anything.

```javascript
const webhook = $('Webhook').item.json.body || {};
const draft = $json.generated_draft || '';
const email = webhook.sender_email || 'unknown@customer.com';
const query = webhook.text || '';

const body = {
  channel: 'customer-ops-triage',
  text: 'New high-confidence triage draft ready for review',
  blocks: [
    { type: 'header',  text: { type: 'plain_text', text: '📥 NEW HIGH-CONFIDENCE TRIAGE DRAFT', emoji: true } },
    { type: 'section', text: { type: 'mrkdwn', text: '*Customer:* ' + email } },
    { type: 'section', text: { type: 'mrkdwn', text: '*Original Query:*\n>' + query } },
    { type: 'section', text: { type: 'mrkdwn', text: '*AI Generated Response:*\n```' + draft + '```' } },
    { type: 'actions', elements: [
      { type: 'button', text: { type: 'plain_text', text: 'Approve & Send', emoji: true },
        style: 'primary', action_id: 'approve_triage_send',
        value: JSON.stringify({ email, draft }) },
      { type: 'button', text: { type: 'plain_text', text: 'Reject & Escalate', emoji: true },
        style: 'danger', action_id: 'reject_triage_escalate', value: 'reject' }
    ] }
  ]
};

return [{ json: { slackBody: body } }];
```

> **Note on button `value` size:** Slack limits an action `value` to 2000 characters. Support drafts in this pipeline are short summaries, so embedding the draft is safe here. For long-form replies, store the draft in Slack message `metadata` or a datastore keyed by ticket ID and pass only that key.

### Node A2: `Post Draft to Slack` (HTTP Request Node)

The card is posted straight to Slack's Web API. Using an explicit HTTP Request keeps the payload fully deterministic and version-controllable (the native Slack node is an equally valid alternative if you prefer credential-managed auth).

* **Method / URL:** `POST https://slack.com/api/chat.postMessage`
* **Headers:**
  * `Content-Type: application/json; charset=utf-8`
  * `Authorization: Bearer {{ $env.SLACK_BOT_TOKEN }}` — the bot token is read from the **n8n instance environment** on the VPS (not the Django `.env`).
* **Body (JSON):** `={{ JSON.stringify($json.slackBody) }}`

## 5. Enforcing Slack Interactivity Callbacks

Once the buttons are rendered, Slack reports the click event back to your VPS. This is handled by a **second, independent trigger chain** in the same workflow.

1. In your Slack App Dashboard, open **Interactivity & Shortcuts** and toggle it **On**.
2. Set the **Request URL** to your n8n interactivity webhook: `https://your-vps-n8n-url.com/webhook/slack-interactive`.

```plaintext
  Slack Interactivity (Webhook /slack-interactive) ──► Parse Interaction ──► Route Approval
                                                                              ├─[approve]─► Dispatch Customer Email ────► Update Card - Approved
                                                                              └─[reject]──► Create Escalation Ticket ──► Update Card - Escalated
```

### Node B1: `Slack Interactivity` (Webhook Trigger)

* **HTTP Method:** POST · **Path:** `slack-interactive`
* **Response Mode:** *On Received* — Slack requires a `200` within 3 seconds, so n8n acknowledges immediately rather than waiting for the workflow to finish.

### Node B2: `Parse Interaction` (Code Node)

Slack sends interaction events as `application/x-www-form-urlencoded` with a single `payload` field containing JSON. This node decodes it and flattens the fields the rest of the chain needs — the clicked `action_id`, the `response_url` (used to update the card in place), and the `{ email, draft }` carried on the approve button.

```javascript
const raw = $input.first().json.body ? $input.first().json.body.payload : undefined;
const payload = typeof raw === 'string' ? JSON.parse(raw) : (raw || {});
const action = (payload.actions && payload.actions[0]) ? payload.actions[0] : {};

let meta = {};
try { meta = JSON.parse(action.value); } catch (e) { meta = {}; }

return [{ json: {
  action_id: action.action_id || '',
  response_url: payload.response_url || '',
  user: payload.user ? payload.user.username : '',
  customer_email: meta.email || '',
  draft: meta.draft || ''
} }];
```

### Node B3: `Route Approval` (IF Node)

Branches on `{{ $json.action_id }} === "approve_triage_send"`. The **true** output dispatches the email to the customer; the **false** output (Reject & Escalate) opens a ticket for a human.

### Node B4 (approve): `Dispatch Customer Email` (Send Email Node)

On approval, the final reply is emailed to the customer. Configure an **SMTP credential** in n8n; the node fields are driven entirely by the parsed payload:

* **To:** `={{ $('Parse Interaction').item.json.customer_email }}`
* **Subject:** `Re: Your Support Request`
* **Text:** `={{ $('Parse Interaction').item.json.draft }}`

### Node B5 (reject): `Create Escalation Ticket` (Jira Node)

**What happens when a human disapproves:** the reject branch does **not** email the customer. Instead it opens a Jira issue so the ticket lands in the human backlog — the same destination as the low-confidence escalations from the Phase 2 Switch, giving you a single queue for everything that needs a person. The issue is pre-filled from the interaction context:

* **Summary:** `Rejected triage draft for {{ customer_email }} — escalated by {{ user }}`
* **Description:** the customer email, the reviewer who rejected it, and the full rejected draft (so the human has everything needed to write a correct reply).

Select your **Project** and **Issue Type** in the node and attach a **Jira credential**. (Prefer a different tracker? Swap this node for Zendesk/Linear/a database insert — only the node changes, not the flow.)

### Nodes B6 / B7: `Update Card - Approved` / `Update Card - Escalated` (HTTP Request Nodes)

Both post back to the interaction's `response_url` with `replace_original: true`, so the original Slack card is swapped for a status line (`✅ Approved & sent to …` or `🚫 Rejected & escalated …`). This gives the reviewing agent immediate visual confirmation and prevents double-clicks on a card that has already been actioned.

## Your Engineering Verification Check

To complete Phase 4 and confirm your governance engine is fully integrated:

1. Set `SLACK_BOT_TOKEN` in the n8n instance environment and configure an SMTP credential for the `Dispatch Customer Email` node.
2. Fire your Phase 2 test query webhook again.
3. Verify that your local Django engine returns the response draft, and n8n immediately posts the formatted Block Kit UI card into your `#customer-ops-triage` channel.
4. Click **[Approve & Send]** and confirm the `slack-interactive` webhook fires, the customer email is dispatched, and the Slack card is replaced with the `✅ Approved & sent` status.
5. Repeat with **[Reject & Escalate]** and confirm a Jira escalation ticket is created **and** the card updates to the `🚫 Rejected & escalated` status.
