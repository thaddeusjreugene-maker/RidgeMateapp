# Ridgeline Teams

Roofing sales for individual reps and whole teams. One app, two kinds of accounts:

- **Individual**: one rep. Map, pins, leads, inspection camera, estimates, routes, commissions.
- **Company**: an owner, managers, reps, and office staff. Everything above, plus the Open Leads board, shared map with who-pinned-what, door ownership, leaderboards, team wins, chat, and an admin panel.

---

## 1. Try it right now (demo mode, no setup)

With `config.js` left blank, the app runs a pretend company called **Demo Roofing Co**. It has reps, leads, open call-ins, messages and territories, and everything is stored on the phone.

1. Make a new GitHub repository, for example `ridgeline-teams`.
2. Upload **everything inside this folder** to the top level of the repo: `index.html`, `app.css`, `config.js`, `sw.js`, `manifest.webmanifest`, the icons, and the `js`, `vendor` and `supabase` folders.
3. In the repo, go to **Settings → Pages**, choose **Deploy from a branch → main → / (root)**, and save. The repo must be public for free Pages.
4. Open the address in Safari, then tap **Share → Add to Home Screen**.
5. Tap the **gear → Demo — view the app as**. Switch between **Jordan** (Director), **Marcus/Dana/Tyler** (reps) and **Kim** (office) to see each role. **Reset demo data** puts it back the way it started.

---

## 2. Go live with real accounts (about 20 minutes, free to start)

The live version uses **Supabase**, which provides logins, the database, photo storage and live chat.

**A. Make the project**
1. Sign up at **supabase.com** and create a **New project**. Pick a region near you (East US) and save the database password somewhere safe.

**B. Load the database**
2. Open **SQL Editor → New query**. Paste the whole file `supabase/schema.sql` and click **Run**. It creates every table, the security rules, and the photo storage. It’s safe to run again later — do that whenever you get an updated schema.sql (this version adds skip zones).

**C. Turn on email sign-in codes**
3. Go to **Authentication → Sign In / Providers** and make sure **Email** is on.
4. Go to **Authentication → Emails → Templates → Magic Link**. Replace the body with:
   ```
   <h2>Your Ridgeline sign-in code</h2>
   <p>Enter this code in the app: <strong>{{ .Token }}</strong></p>
   ```
   Do the same for the **Confirm signup** template. The app signs people in with a 6-digit code, not a link.
5. **Set up email sending** under **Authentication → Emails → SMTP Settings**. Supabase's built-in email sends only about 2 emails an hour, and only to people on your Supabase team, so your reps won't get codes without this. The quickest option is your iCloud mail: host `smtp.mail.me.com`, port `587`, username = your full iCloud email address, password = an app-specific password from account.apple.com → Sign-In and Security → App-Specific Passwords, sender email = the same iCloud address. Then raise **Authentication → Rate Limits → emails per hour** to about 30.

**D. Connect the app**
6. Go to **Project Settings → API Keys**. Copy the **Project URL** (also shown under the green **Connect** button) and the **Publishable key** (starts with `sb_publishable_`). The older **anon** key on the Legacy tab works too.
7. Open `config.js`, paste them between the quotes, and upload the file to GitHub:
   ```js
   window.RIDGELINE_CONFIG = {
     supabaseUrl: 'https://xxxxx.supabase.co',
     supabaseAnonKey: 'sb_publishable_...'
   };
   ```
   This key is safe to publish. The database rules decide who can see what.

**E. First sign-in**
8. Open the app and sign in with your email and the code. Choose **Start a company** and enter the company name. You're the **Owner**.
9. Go to **Admin → People** and tap **+ Rep code**. Copy the invite text and text it to the rep. The link has the code built in: when they open it in Safari, sign in, and reach the welcome screen, the code is already filled in. If they add the app to their home screen first, they type the code once.

---

## 3. How the company rules work

| Rule | Where to change it |
|---|---|
| Contact deadline for claimed office leads (default 2 hours, then back to the board) | Admin → Lead rules |
| Claim limit (default 3 unworked at once) | Admin → Lead rules |
| Door protection window (default 30 days) | Admin → Lead rules |
| Reps see teammates' pins (status color + who pinned it, never names or phones) | Admin → Lead rules |
| Leaderboards on/off (commissions are never shown) | Admin → Lead rules |
| Commission % by job type, separately for self-generated vs company leads, plus per-rep overrides | Admin → Commissions |
| Team goal bar | Admin → Goals |
| Territories (draw on the map, assign reps) | Admin → Territories |
| Skip zones (areas nobody should knock — new roofs, no soliciting) | Map → Skip. Anyone can draw one; everyone sees it. Only the person who drew it or a manager can change it. |

**Who sees what**
- **Owner / Manager:** every lead, every pin with GPS check, the board, reports and settings. They **cannot** read direct messages.
- **Office:** every lead and photo, and can post leads. No commissions, no admin.
- **Rep:** their own leads. Teammates' pins show status and who pinned them. The Open Leads board shows only the area until a lead is claimed.
- **Everyone:** the storm tracker, live NWS warnings, pitch gauge, roof calculator and the other tools; their own color and appearance settings.
- **Direct messages** are private to the two people in them. Only the **Owner** can export all messages, for a legal dispute (Admin → Company).
- **When someone is removed,** their customers, photos and notes stay with the company.

---

## 4. Not in this version yet

- **Push notifications to the lock screen.** Needs the App Store version. New messages and leads show inside the app.
- **Billing and subscriptions.** Needed before selling to other companies, using Stripe.
- **Texting homeowners from the app.** Needs a business number and carrier registration.
- **AI roof visualizer.**
- **Hail swath maps.** The storm tracker uses free NWS storm reports (points). Radar hail swaths need a paid service.

## 5. Costs

- **Supabase:** free to start. The paid plan is about $25/month when you outgrow it.
- **GitHub Pages:** free.
- **Map:** Esri satellite. Add a Mapbox key in Settings for sharper imagery; it has a large free tier. Commercial use at scale needs paid map accounts.
- **Apple Developer:** $99/year, only when you build the App Store version.

## Files

```
index.html            page shell
app.css               styles
config.js             your Supabase keys (blank = demo)
js/app.js             the app
js/api/supabase.js    live backend
js/api/demo.js        demo company
js/api/shape.js       lead ↔ database conversion
supabase/schema.sql   database, security rules, functions — run once in Supabase
vendor/               map library
sw.js                 offline support
```
