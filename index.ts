// OPTIONAL: emails you whenever a contact message or project request arrives.
// Set up steps are in the README ("Email notifications"). Not tested against
// your project: deploy it, then submit a test message to confirm.
//
// Secrets this function needs (supabase secrets set ...):
//   RESEND_API_KEY   API key from resend.com
//   NOTIFY_TO        the address that receives alerts, e.g. fawaazmahama@gmail.com
//   WEBHOOK_SECRET   any long random string; also set it as a header on the webhook

const esc = (s: unknown) =>
  String(s ?? "").replace(/[&<>"']/g, (c) =>
    ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]!)
  );

Deno.serve(async (req) => {
  if (req.headers.get("x-webhook-secret") !== Deno.env.get("WEBHOOK_SECRET")) {
    return new Response("forbidden", { status: 403 });
  }

  const { table, record } = await req.json();
  let subject = "";
  let html = "";
  let replyTo: string | undefined;

  if (table === "messages") {
    subject = `New message from ${record.name}`;
    replyTo = record.email;
    html = `<p><b>${esc(record.name)}</b> (${esc(record.email)})<br>Service: ${esc(record.service)}</p><p>${esc(record.message).replace(/\n/g, "<br>")}</p>`;
  } else if (table === "client_projects") {
    subject = `New project request: ${record.project_title}`;
    html = `<p><b>${esc(record.project_title)}</b><br>Service: ${esc(record.service_type)}<br>Budget: ${record.budget_ghc ? "GH₵ " + esc(record.budget_ghc) : "not given"}<br>Client: ${esc(record.client_name)} (${esc(record.client_email)})</p>`;
    replyTo = record.client_email;
  } else {
    return new Response("ignored");
  }

  const res = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${Deno.env.get("RESEND_API_KEY")}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      from: "Tech Labs <onboarding@resend.dev>",
      to: [Deno.env.get("NOTIFY_TO")],
      subject,
      html,
      ...(replyTo ? { reply_to: replyTo } : {}),
    }),
  });

  return new Response(res.ok ? "ok" : "email failed", { status: res.ok ? 200 : 502 });
});
