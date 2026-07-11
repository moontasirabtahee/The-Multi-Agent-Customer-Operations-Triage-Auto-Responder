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

## 4. Configuring n8n Nodes for Interaction

### Node A: The Block Kit Formatter (Slack Node)

Place this node right after your Phase 3 HTTP Request success branch. Set the action to **Post Message**. In the **Blocks** parameter configuration field, inject this production-grade layout JSON:  

```json
[  
  {  
    "type": "header",  
    "text": { "type": "plain_text", "text": "📥 NEW HIGH-CONFIDENCE TRIAGE DRAFT" }  
  },  
  {  
    "type": "section",  
    "text": {  
      "type": "mrkdwn",  
      "text": "*Original Query:*\n>{{ $('Webhook').item.json.body.text }}"  
    }  
  },  
  {  
    "type": "section",  
    "text": {  
      "type": "mrkdwn",  
      "text": "*AI Generated Response:*\n```{{ $json.generated_draft }}```"  
    }  
  },  
  {  
    "type": "actions",  
    "elements": [  
      {  
        "type": "button",  
        "text": { "type": "plain_text", "text": "Approve & Send" },  
        "style": "primary",  
        "value": "approve",  
        "action_id": "approve_triage_send"  
      },  
      {  
        "type": "button",  
        "text": { "type": "plain_text", "text": "Reject & Escalate" },  
        "style": "danger",  
        "value": "reject",  
        "action_id": "reject_triage_escalate"  
      }  
    ]  
  }  
]
```

### Node B: Enforcing Slack Interactivity Callbacks

Once the button is rendered, Slack needs to report the mouse click event back to your VPS.

1. In your Slack App Dashboard, click **Interactivity & Shortcuts** and toggle it to **On**.  
2. You will see a **Request URL** text field. This must target a new, separate **Webhook Trigger Node** inside your n8n workspace canvas.  
3. Configure your new n8n Webhook node:  
   * **HTTP Method:** POST  
   * **Path:** slack-interactive  
4. Copy the production URL given by n8n (e.g., `https://your-vps-n8n-url.com/webhook/slack-interactive`) and paste it back into the Slack Request URL text box.

## Your Engineering Verification Check

To complete Phase 4 and confirm your governance engine is fully integrated:

1. Fire your Phase 2 test query webhook again.  
2. Verify that your local Django engine returns the response draft, and n8n immediately posts the formatted Block Kit UI card directly into your Slack channel.  
3. Click the **[Approve & Send]** button in your Slack app interface and confirm that your inbound `slack-interactive` webhook node successfully intercepts the incoming click payload event.
