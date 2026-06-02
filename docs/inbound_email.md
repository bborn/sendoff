# Inbound email (BCC) ingress

Sendoff records every outbound sales email and every reply as a
`Sendoff::EmailEvent`, matched to the lead, company, and thread. It learns about
those messages through a single provider-agnostic webhook:

```
POST <mount>/inbound_emails
```

where `<mount>` is wherever the host app mounted the engine (e.g. `/sendoff`,
giving `POST /sendoff/inbound_emails`).

Point a mail provider at this endpoint two ways:

- **BCC your outbound mail** to a routing address. Sendoff sees the From is one
  of your `Sendoff::EmailAccount`s and records the copy as an **outbound** event,
  matched to the recipient lead.
- **Forward replies** to the same address. Sendoff sees an external From and
  records an **inbound** event, matched to the sender lead.

No ActionMailbox, no ActiveStorage — just a controller and the `mail` gem.

## Authentication (fail closed)

Set a shared secret:

```
SENDOFF_INBOUND_SECRET=<a long random string>
```

Every request must present it. If the env var is blank, or the token is missing
or wrong, the endpoint returns `401`. Two ways to present it:

- **Header (preferred):** `X-Sendoff-Token: <secret>`
- **HTTP Basic:** any username, password = the secret (for providers that only
  support Basic auth).

The comparison is constant-time (`ActiveSupport::SecurityUtils.secure_compare`).

## Request formats

The endpoint accepts either raw MIME or pre-parsed fields.

### Raw RFC822 (preferred — full fidelity)

Send the raw message as the request body with
`Content-Type: message/rfc822`, **or** in an `email`, `raw`, or `message`
form/JSON param. Sendoff parses it with `Mail.new`.

### Pre-parsed fields

Providers that pre-parse can POST discrete fields (form-encoded or JSON):

| field         | notes                                  |
| ------------- | -------------------------------------- |
| `from`        | sender address                         |
| `to`          | comma-separated or array               |
| `cc`, `bcc`   | comma-separated or array               |
| `subject`     |                                        |
| `text`        | plain-text body (preferred)            |
| `html`        | HTML body (stripped if no text)        |
| `message_id`  | RFC Message-ID — idempotency key       |
| `in_reply_to` | parent Message-ID (threads the reply)  |
| `references`  | space-separated Message-IDs            |
| `date`        | parseable date; defaults to now        |

## Responses

| status            | meaning                                        |
| ----------------- | ---------------------------------------------- |
| `204 No Content`  | recorded (or already recorded — idempotent)    |
| `401 Unauthorized`| secret unset, or token missing/wrong           |
| `422 Unprocessable Entity` | body could not be parsed at all       |

Idempotency is keyed on the RFC `Message-ID`; re-delivering the same message
never creates a duplicate event.

## Provider setup

### 1. Cloudflare Email Routing + Email Worker (preferred)

Cloudflare can route a custom address (e.g. `inbox@yourdomain.com`) to a Worker.
The Worker reads the raw message and POSTs it to Sendoff.

1. In the Cloudflare dashboard, enable **Email → Email Routing** for your domain
   and verify the MX records.
2. Create a Worker and bind it as the destination for your routing address.
3. Add the secret: `npx wrangler secret put SENDOFF_INBOUND_SECRET`.
4. Deploy the Worker below.

```js
// wrangler.toml
//   name = "sendoff-inbound"
//   main = "src/worker.js"
//   compatibility_date = "2024-09-01"
//   [vars]
//   SENDOFF_URL = "https://your-host.example.com/sendoff/inbound_emails"

export default {
  async email(message, env, ctx) {
    // message.raw is a ReadableStream of the full RFC822 source.
    const raw = await new Response(message.raw).arrayBuffer();

    const res = await fetch(env.SENDOFF_URL, {
      method: "POST",
      headers: {
        "Content-Type": "message/rfc822",
        "X-Sendoff-Token": env.SENDOFF_INBOUND_SECRET,
      },
      body: raw,
    });

    if (!res.ok) {
      // Reject so Cloudflare retries / bounces rather than silently dropping.
      throw new Error(`Sendoff ingest failed: ${res.status}`);
    }
  },
};
```

Then BCC `inbox@yourdomain.com` on your outbound mail (and auto-forward replies
to it). Outbound copies become `outbound` events; replies become `inbound`.

### 2. SendGrid Inbound Parse

SendGrid POSTs a `multipart/form-data` request with parsed fields, which maps
directly onto the pre-parsed shape above.

1. Point an MX record (e.g. `parse.yourdomain.com`) at `mx.sendgrid.net`.
2. In **Settings → Inbound Parse**, add a host and set the destination URL to
   `https://your-host.example.com/sendoff/inbound_emails`.
3. SendGrid cannot add a custom header, so authenticate via HTTP Basic by
   embedding the secret in the URL:
   `https://provider:<SENDOFF_INBOUND_SECRET>@your-host.example.com/sendoff/inbound_emails`
   (any username; password = the secret).

SendGrid sends `from`, `to`, `subject`, `text`, `html`, and the raw `email`
field — all of which the endpoint understands.

### 3. Mailgun routes

1. Add and verify your domain in Mailgun.
2. Create a **Route** with a filter (e.g. `match_recipient("inbox@yourdomain.com")`)
   and the action
   `forward("https://your-host.example.com/sendoff/inbound_emails")`.
3. Mailgun cannot add a custom header on a `forward()` action, so use HTTP Basic
   in the URL just like SendGrid:
   `forward("https://provider:<SENDOFF_INBOUND_SECRET>@your-host.example.com/sendoff/inbound_emails")`.

Mailgun posts parsed fields (`from`, `recipient`/`to`, `subject`,
`body-plain` → map to `text`, `body-html` → `html`) plus the raw MIME in
`body-mime`; either path works.

## Environment

| var                     | required | purpose                              |
| ----------------------- | -------- | ------------------------------------ |
| `SENDOFF_INBOUND_SECRET`| yes      | shared secret for the webhook (401 if blank) |
