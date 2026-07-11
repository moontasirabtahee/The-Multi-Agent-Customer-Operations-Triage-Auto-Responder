/**
 * Gmail -> n8n ingress forwarder (Google Apps Script).
 *
 * Runs on a time-driven trigger, finds EVERY unread inbox email, and POSTs each
 * one to the n8n `triage` webhook as { text, sender_email, subject }. Each message
 * is marked read only after it is successfully forwarded (2xx), so a failed send
 * is retried on the next run.
 *
 * SETUP:
 *   1. script.google.com -> New Project -> paste this file.
 *   2. Left sidebar -> Triggers (clock icon) -> Add Trigger:
 *        function: forwardGmailToN8n | event source: Time-driven | e.g. every 5 minutes.
 *   3. Run once manually to grant Gmail permission, then check Executions for the log.
 *
 * NOTE: n8nWebhookUrl below is the Cloudflare quick-tunnel URL that fronts the
 * VPS n8n instance. Quick-tunnel hostnames are EPHEMERAL — they change every time
 * cloudflared restarts on the VPS, so update this value whenever that happens.
 * Always use the production path `/webhook/triage` (NOT `/webhook-test/triage`,
 * which only responds while you are actively clicking "Listen for test event").
 */
function forwardGmailToN8n() {
  // Cloudflare tunnel URL fronting the VPS n8n webhook (ephemeral — see note above).
  var n8nWebhookUrl = "https://respiratory-direct-plenty-person.trycloudflare.com/webhook/triage";

  Logger.log("Starting Gmail to n8n forwarder script...");

  // Every unread message currently in the inbox.
  var searchQuery = "is:unread label:inbox";
  var threads = GmailApp.search(searchQuery);
  Logger.log("Found " + threads.length + " unread thread(s).");

  if (threads.length === 0) {
    Logger.log("No unread inbox threads found. Exiting.");
    return;
  }

  var forwarded = 0;
  var failed = 0;

  for (var t = 0; t < threads.length; t++) {
    var messages = threads[t].getMessages();

    for (var m = 0; m < messages.length; m++) {
      var message = messages[m];
      if (!message.isUnread()) {
        continue; // only forward unread messages within the thread
      }

      var rawFrom = message.getFrom();
      var emailMatch = rawFrom.match(/<([^>]+)>/);
      var senderEmail = emailMatch ? emailMatch[1] : rawFrom;

      var payload = {
        sender_email: senderEmail,
        text: message.getPlainBody(),
        subject: message.getSubject()
      };

      var options = {
        method: "post",
        contentType: "application/json",
        payload: JSON.stringify(payload),
        muteHttpExceptions: true
      };

      try {
        var response = UrlFetchApp.fetch(n8nWebhookUrl, options);
        var responseCode = response.getResponseCode();

        if (responseCode >= 200 && responseCode < 300) {
          message.markRead();
          forwarded++;
          Logger.log("Forwarded + marked read: " + senderEmail + " | " + message.getSubject());
        } else {
          failed++;
          Logger.log("Failed (HTTP " + responseCode + "): " + message.getSubject() +
                     " -> " + response.getContentText());
        }
      } catch (e) {
        failed++;
        Logger.log("Error forwarding '" + message.getSubject() + "': " + e.toString());
      }
    }
  }

  Logger.log("Done. Forwarded: " + forwarded + ", Failed: " + failed);
}
