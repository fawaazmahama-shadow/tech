# Tech Labs website

Single-page site (plain HTML/CSS/JS) hosted on GitHub Pages, with Supabase for sign-in, the contact form, the client dashboard and the admin portal.

Live: https://fawaazmahama-shadow.github.io/tech/

## Files

| Path | What it is |
| --- | --- |
| `index.html` | The whole site (pages, styles, script) |
| `vendor/supabase.js` | supabase-js 2.45.4, hosted here instead of a CDN |
| `supabase/schema.sql` | Tables, Row Level Security policies, triggers, admin role |
| `supabase/functions/notify-new-request/` | Optional email alerts for new requests |
| `favicon.svg`, `og-image.png` | Browser icon and link-preview image |
| `404.html`, `robots.txt`, `sitemap.xml` | Not-found page and search engine files |

## Deploy, in this order

1. **Run the database script.** Supabase > SQL Editor > paste all of `supabase/schema.sql` > Run. It replaces all old policies on the three tables with strict ones and makes `fawaazmahama@gmail.com` an admin.
2. **Supabase > Authentication > URL Configuration.** Site URL: `https://fawaazmahama-shadow.github.io/tech/`. Under Redirect URLs add `https://fawaazmahama-shadow.github.io/tech/**`.
3. **Supabase > Authentication settings.** Set the minimum password length to 8 or more, and keep "Confirm email" on.
4. **Upload everything** in this folder to the GitHub repo (Add file > Upload files, keep the folder structure). Pages redeploys in about a minute.
5. **Log out and log in again** on the live site so your login picks up the admin role. The Admin link then appears in the menu.

## Test after deploying

- Send a contact message while logged out. It should appear in the Admin Portal.
- Sign up a second test account. It must not see the first account's projects or messages.
- Sign in with Google and with email. Both should land on your account page.
- Send a message containing `<b>hi</b>`. It should display as plain text, not bold.
- As a client, reply on a project; the sender name should come from the account, not from anything typed.

## Things only you can fill in

- **Testimonials** on the home page are anonymous. Replace them with real names, with permission.
- **Portfolio:** add entries to `PORTFOLIO` in the script (top of the `<script>` block). A "Work" page and menu link appear automatically. Put screenshots in an `images/` folder.
- **About photo:** set `ABOUT_PHOTO` (for example `"images/me.jpg"`).
- **Business email:** a domain email looks more established than Gmail. When you have one, search `index.html` for `fawaazmahama@gmail.com` and replace it (and update `supabase/schema.sql` step 8 if it becomes your login).
- **Training tools:** the Services page says "Design and productivity tools". Name the ones you teach.
- **Data protection:** the privacy page is a plain-language notice, not legal advice. Check whether registering with Ghana's Data Protection Commission applies to you.

## Email notifications (optional)

Without this you only see new requests when the Admin Portal is open (it updates live and shows a pop-up).

1. Create a free account at resend.com and copy an API key.
2. With the Supabase CLI: `supabase functions deploy notify-new-request --no-verify-jwt`, then `supabase secrets set RESEND_API_KEY=... NOTIFY_TO=you@example.com WEBHOOK_SECRET=any-long-random-string`.
3. Supabase > Database > Webhooks: create two webhooks (tables `messages` and `client_projects`, event Insert, type HTTP Request, URL = the function URL). Add the HTTP header `x-webhook-secret` with the same secret.

## Design decisions worth knowing

- **Pages use `#/` links.** This keeps the site on one static file and works with GitHub Pages, but search engines treat every page as the home page. Titles and descriptions update per page for people, and the home page carries full business details for Google. Separate URLs per page would be the next SEO step.
- **`robots.txt` and `sitemap.xml` sit under `/tech/`.** Search engines only read `robots.txt` at the very root of a domain, so that file is ignored here. The sitemap still helps if you submit it in Google Search Console.
- **Admin is checked in the database**, not the browser. The Admin link is only a convenience; Row Level Security enforces access.
- **Content Security Policy** (a meta tag in `index.html`) limits what the page can load and contact. If you add an analytics script, embedded map or external image host, add its domain there or it will be blocked.
- The Supabase **publishable key** in `index.html` is meant to be public. Never commit a `service_role` or secret key.
