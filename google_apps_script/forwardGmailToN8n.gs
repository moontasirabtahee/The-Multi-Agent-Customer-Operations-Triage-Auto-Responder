/**
 * Gmail -> n8n ingress forwarder (Google Apps Script).
 *
 * Runs on a time-driven trigger, finds the latest unread inbox email received
 * today, and POSTs it to the n8n `triage` webhook as { text, sender_email, subject }.
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

  var today = new Date();
  var dateString = today.getFullYear() + "/" + (today.getMonth() + 1) + "/" + today.getDate();
  var searchQuery = "is:unread label:inbox after:" + dateString;

  var threads = GmailApp.search(searchQuery);
  Logger.log("Found " + threads.length + " matching unread threads.");

  if (threads.length === 0) {
    Logger.log("No unread threads found for today. Exiting.");
    return;
  }

  var latestThread = threads[0];
  var messages = latestThread.getMessages();

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
    validateHttpsCertificates: false, // Tunnel cert is valid; kept lenient for flexibility.
    muteHttpExceptions: true
  };

  Logger.log("Forwarding message from: " + senderEmail);

  try {
    var response = UrlFetchApp.fetch(n8nWebhookUrl, options);
    var responseCode = response.getResponseCode();
    var responseBody = response.getContentText();

    Logger.log("n8n Response Code: " + responseCode);
    Logger.log("n8n Response Body: " + responseBody);

    if (responseCode >= 200 && responseCode < 300) {
      latestMessage.markRead();
      Logger.log("Message forwarded successfully and marked as read.");
    } else {
      Logger.log("Failed to forward. Webhook returned status: " + responseCode);
    }
  } catch (e) {
    Logger.log("Error sending fetch call: " + e.toString());
  }
}
