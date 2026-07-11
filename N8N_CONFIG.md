# n8n Configuration Reference

Concrete values to plug into the imported workflow (`n8n/CustomerOpsTriageEngine.json`)
after **Workflows → Import from File**. Anything in `< >` is a secret or an
environment-specific value you supply.

> **Tunnel URLs are ephemeral.** The `trycloudflare.com` quick-tunnel hostnames change
> every time `cloudflared` restarts. Re-copy them into the nodes below after each launch,
> or set up a **named tunnel** for stable URLs. The examples shown are from one run and
> will not resolve later.

---

## 0. Credentials to create in n8n (Credentials → New)

| Credential | Used by node(s) | Notes |
| :--- | :--- | :--- |
| **Slack API** (Bot token) *or* env `SLACK_BOT_TOKEN` | `Post Draft to Slack` | Bot token `xoxb-…` |
| **SMTP** | `Dispatch Customer Email` | Your outbound mail server |
| **Jira Software Cloud** | `Create an issue`, `Create Escalation Ticket` | API token + site URL |

## 1. n8n instance environment variables

| Variable | Value | Consumed by |
| :--- | :--- | :--- |
| `SLACK_BOT_TOKEN` | `<xoxb-your-slack-bot-token>` | `Post Draft to Slack` (`Authorization: Bearer …`) |

## 2. Traffic map & the THREE Cloudflare tunnels

There are **three** cloudflared quick tunnels, in two directions. Getting them confused is
the single most common cause of "nothing works":

```
  Gmail / Slack ──► VPS n8n            (tunnel #3, runs ON THE VPS)
                       │
   VPS n8n ───────────┼──► Django RAG  (tunnel #1, from pipeline.ps1 on your PC)
                       └──► Ollama LLM  (tunnel #2, from pipeline.ps1 on your PC)
```

| # | Tunnel | Runs on | Fronts | Used by |
| :-- | :--- | :--- | :--- | :--- |
| 1 | Django RAG | your PC (`pipeline.ps1`) | `127.0.0.1:8520` | n8n `HTTP Request` node |
| 2 | Ollama LLM | your PC (`pipeline.ps1`) | `127.0.0.1:11434` | n8n `OpenAI Chat Model` nodes |
| 3 | VPS n8n | the VPS | `127.0.0.1:5678` (n8n) | Gmail Apps Script + Slack callbacks |

Tunnels #1 and #2 are opened automatically by `pipeline.ps1`, which prints the fresh URLs
at the end of every run. Tunnel #3 you start on the VPS:
```bash
cloudflared tunnel --url http://127.0.0.1:5678
```

> **Ollama tunnel (#2)** must use `--http-host-header localhost:11434` (baked into
> `pipeline.ps1`) or Ollama returns 403 for the proxied Host header. n8n (#3) needs no such flag.

> **VPS port must be pinned.** The Hostinger n8n compose defaults to `ports: - "5678"`,
> which assigns a **random** host port that changes on every `docker restart` and silently
> breaks tunnel #3. Pin it: `ports: - "127.0.0.1:5678:5678"`, then point cloudflared at 5678.

> **Every quick-tunnel URL is ephemeral** — it changes when its cloudflared restarts, so all
> four paste targets below (2 in n8n nodes, 1 in Slack, 1 in the Gmail script) must be
> re-updated after a restart. A **named tunnel** (needs a domain) makes them stable.

## 2b. Activating the workflow (webhook registration)

The production webhook `/webhook/triage` only exists while the workflow is **Active**.
After importing the workflow it is `active: false`, and — importantly — **toggling Active
from the n8n UI is the only reliable way to register the webhook.** Activating via the CLI
(`n8n update:workflow --active=true`) or a container restart logs "Activated workflow" but
leaves the endpoint returning `404 not registered`. If Gmail/Slack get a 404, open the
workflow and flip the **Active** switch (top-right).

## 3. Node-by-node values

| Node | Field | Value to set |
| :--- | :--- | :--- |
| `OpenAI Chat Model` / `OpenAI Chat Model1` | Base URL | `https://<your-ollama-tunnel>.trycloudflare.com/v1` |
| | Model | `gemma4:e2b` (or whatever chat model you pulled) |
| | Temperature | `0` (Classifier) / `0.1` (Assessor) — already set |
| `HTTP Request` (RAG call) | Method / URL | `POST https://<your-django-tunnel>.trycloudflare.com/api/v1/triage/rag/` |
| | Body (JSON) | `={{ JSON.stringify({ text: $('Webhook').item.json.body.text }) }}` (already set) |
| `Post Draft to Slack` | URL | `https://slack.com/api/chat.postMessage` (already set) |
| | Header `Authorization` | `Bearer {{ $env.SLACK_BOT_TOKEN }}` (already set) |
| | Slack channel | `customer-ops-triage` → change to your channel in `Build Slack Card` |
| `Slack Interactivity` | Webhook path | `slack-interactive` (already set) |
| `Dispatch Customer Email` | Credential | your **SMTP** credential |
| | From | `support@enterprise.com` → your sender address |
| | To / Subject / Text | driven by `Parse Interaction` (already set) |
| `Create an issue` / `Create Escalation Ticket` | Project + Issue Type | select yours; attach **Jira** credential |
| `Update Card - Approved` / `Update Card - Escalated` | URL | `={{ $('Parse Interaction').item.json.response_url }}` (already set) |

## 4. Slack App setup

1. api.slack.com/apps → **Create New App → From Scratch**.
2. **OAuth & Permissions → Bot Token Scopes:** `chat:write`, `chat:write.public`. Install to workspace, copy the **Bot User OAuth Token** (`xoxb-…`) into `SLACK_BOT_TOKEN`. Note: `chat.postMessage` needs a `Bearer` **bot** (`xoxb-`) token — an app-level (`xapp-`) token will fail with `invalid_auth`.
3. **Interactivity & Shortcuts → On → Request URL:** your **VPS n8n tunnel** (#3) + path —
   `https://<vps-n8n-tunnel>.trycloudflare.com/webhook/slack-interactive`

> ⚠️ **Never paste a token directly into the node's Authorization header.** n8n exports it as
> plaintext, and GitHub push-protection will block the push (and the token is then leaked).
> Use `=Bearer {{ $env.SLACK_BOT_TOKEN }}` (already set) with the env var, or an n8n credential.

## 5. Local backend `.env` (reference)

The real `backend/.env` is git-ignored. These are the working non-secret values the
local RAG engine expects (mirror of `backend/.env.example`); secrets are redacted:

```dotenv
DEBUG=True
ALLOWED_HOSTS=localhost,127.0.0.1,.trycloudflare.com
DB_NAME=customer_ops
DB_USER=postgres
DB_PASSWORD=postgres          # pgvector Docker container default
DB_HOST=127.0.0.1
DB_PORT=5544                  # host port for the pgvector container
OLLAMA_HOST=http://127.0.0.1:11434
OLLAMA_LLM_MODEL=gemma4:e2b   # must match a model you pulled
OLLAMA_EMBED_MODEL=nomic-embed-text   # 768-dim
SECRET_KEY=<generated by pipeline.ps1>
SLACK_BOT_TOKEN=<xoxb-... — only needed by n8n, not Django>
SLACK_APP_ID=<Slack App ID>
SLACK_CLIENT_ID=<Slack Client ID>
SLACK_CLIENT_SECRET=<Slack Client Secret>
SLACK_SIGNING_SECRET=<Slack Signing Secret>
SLACK_VERIFICATION_TOKEN=<Slack Verification Token>
JIRA_API_TOKEN=<Jira API Token>
JIRA_EMAIL=<Jira email address>
JIRA_SITE_URL=<Jira site URL>
```


---

## 6. Connecting to Gmail

To send emails using your Gmail account in n8n, you have two options: **SMTP (Recommended for current workflow)** or the **Gmail OAuth2 Node**.

### Option A: Connect via SMTP (App Password)
This is the easiest way to configure the existing `Dispatch Customer Email` node.

#### Step 1: Generate a Google App Password
Since Google deprecated "Less Secure Apps", you must use an App Password:
1. Go to your **[Google Account Security Settings](https://myaccount.google.com/security)**.
2. Ensure **2-Step Verification** is turned **ON** (this is required to use App Passwords).
3. Click on **2-Step Verification** and scroll down to the very bottom to find **App passwords**.
4. Enter a name for the app (e.g., `n8n Customer Ops`) and click **Create**.
5. Copy the generated **16-character password** (e.g., `abcd efgh ijkl mnop`).

#### Step 2: Configure SMTP Credentials in n8n
1. In n8n, go to **Credentials** → **Add Credential** → search for **SMTP**.
2. Fill in the credentials as follows:
   * **User:** `your-email@gmail.com`
   * **Password:** `<The 16-character App Password generated above>`
   * **Host:** `smtp.gmail.com`
   * **Port:** `465` (SSL) or `587` (TLS)
   * **SSL/TLS:** Enable/Check the box if using port 465.

#### Step 3: Update the Workflow Node
1. Open the `Dispatch Customer Email` node.
2. Select your newly created SMTP credential.
3. Update the **From** field to match your Gmail address: `your-email@gmail.com`.

---

### Option B: Connect via Native Gmail Node (OAuth2)
If you want to read/send emails securely via API rather than SMTP, you can swap the node:

1. Replace the `Dispatch Customer Email` (SMTP) node with a native **Gmail Node** set to **Send Email**.
2. Add a new credential for **Gmail OAuth2 API**.
3. Choose whether to use n8n's cloud service/credentials (if using n8n cloud) or register a custom OAuth client in Google Cloud Console.
4. Authenticate your Gmail account via the OAuth consent screen.
5. Map the **To**, **Subject**, and **Body** parameters in the node.

---

## 7. Triggering the Workflow via Gmail (Ingress Forwarding)

Your n8n workflow starts with a **Webhook Trigger** on `/webhook/triage`, so new Gmail
messages are forwarded to it by a **Google Apps Script** — no change to the workflow nodes.

> **Canonical script:** the maintained version lives in the repo at
> **[`google_apps_script/forwardGmailToN8n.gs`](google_apps_script/forwardGmailToN8n.gs)** and
> forwards **every** unread inbox message (marking each read only on a 2xx). The copy inlined
> below is an older single-message illustration — prefer the repo file.
>
> Set `n8nWebhookUrl` to your **VPS n8n tunnel** (#3) + the **production** path:
> `https://<vps-n8n-tunnel>.trycloudflare.com/webhook/triage` — NOT `/webhook-test/…`, which
> only responds while you are clicking "Listen for test event", and NOT the raw
> `…hstgr.cloud` host (which isn't reachable externally).

### Google Apps Script Setup (Automatic Forwarder)

1. Open **[Google Apps Script](https://script.google.com/)** and click **New Project**.
2. Replace any default code with the following script:

```javascript
function forwardGmailToN8n() {
  // VPS n8n cloudflared tunnel (#3) + PRODUCTION path. Update after each tunnel restart.
  var n8nWebhookUrl = "https://<vps-n8n-tunnel>.trycloudflare.com/webhook/triage";
  
  Logger.log("Starting Gmail to n8n forwarder script...");
  
  // Get today's date in YYYY/MM/DD format (e.g. 2026/07/11)
  var today = new Date();
  var dateString = today.getFullYear() + "/" + (today.getMonth() + 1) + "/" + today.getDate();
  
  // 2. Search for unread emails in the Inbox received on or after today
  var searchQuery = "is:unread label:inbox after:" + dateString;
  Logger.log("Gmail search query: " + searchQuery);
  
  var threads = GmailApp.search(searchQuery);
  Logger.log("Found " + threads.length + " matching unread threads.");
  
  if (threads.length === 0) {
    Logger.log("No unread threads found for today. Exiting.");
    return;
  }
  
  // 3. Process ONLY the single most recent thread
  var latestThread = threads[0];
  var messages = latestThread.getMessages();
  
  // Find the most recent unread message inside the thread
  var latestMessage = null;
  for (var k = messages.length - 1; k >= 0; k--) {
    if (messages[k].isUnread()) {
      latestMessage = messages[k];
      break;
    }
  }
  
  if (!latestMessage) {
    Logger.log("No unread messages found in the latest thread.");
    return;
  }
  
  var rawFrom = latestMessage.getFrom();
  var emailMatch = rawFrom.match(/<([^>]+)>/);
  var senderEmail = emailMatch ? emailMatch[1] : rawFrom;
  
  var payload = {
    sender_email: senderEmail,
    text: latestMessage.getPlainBody(),
    subject: latestMessage.getSubject()
  };
  
  var options = {
    method: "post",
    contentType: "application/json",
    payload: JSON.stringify(payload),
    muteHttpExceptions: true
  };
  
  Logger.log("Forwarding ONLY the single most recent unread message from today (Sender: " + senderEmail + ")...");
  
  try {
    var response = UrlFetchApp.fetch(n8nWebhookUrl, options);
    var responseCode = response.getResponseCode();
    var responseBody = response.getContentText();
    
    Logger.log("n8n Response Code: " + responseCode);
    Logger.log("n8n Response Body: " + responseBody);
    
    if (responseCode >= 200 && responseCode < 300) {
      latestMessage.markRead(); // Only mark email read on successful 2xx response
      Logger.log("Message forwarded successfully and marked as read.");
    } else {
      Logger.log("Failed to forward. Webhook returned status: " + responseCode);
    }
  } catch (e) {
    Logger.log("Error sending fetch call: " + e.toString());
  }
  
  Logger.log("Script run complete.");
}

```

3. Click **Save** (disk icon).
4. Click on the **Triggers** icon (clock icon on the left sidebar) → **Add Trigger**:
   * **Choose which function to run:** `forwardGmailToN8n`
   * **Choose which deployment should run:** `Head`
   * **Select event source:** `Time-driven`
   * **Select type of time based trigger:** `Minutes timer`
   * **Select minute interval:** `Every minute` (or set a longer interval like every 5/10 minutes).
5. Click **Save** and authorize the script when prompted by Google.

---

### Active Google Apps Script Deployment
* **Web App URL:** `https://script.google.com/macros/s/AKfycbzciBZIDRyBloPc87XAWrqWWduhuZfehk7TpKZlKnEiO-xi0An3KTk95MDqU9hFXrqy/exec`
* **Deployment ID:** `AKfycbzciBZIDRyBloPc87XAWrqWWduhuZfehk7TpKZlKnEiO-xi0An3KTk95MDqU9hFXrqy`

---

### Alternative: Native Gmail Trigger in n8n
If you do not want to use Google Apps Script, you can alternatively delete the `Webhook` trigger node on your n8n canvas and insert a native **Gmail Trigger** node (`n8n-nodes-base.gmailTrigger`). Note that this requires configuring Gmail OAuth API access inside your Google Developer Console to allow n8n to listen to your account.




