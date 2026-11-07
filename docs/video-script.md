# Presentation video: script (target 7 minutes, limit 5–8)

The brief asks for a live demonstration of: the reskin, the deployed system running in AWS, the dashboard and alarms, the restore, and the fault, following the website's structure. Record your screen with your voice (OBS, or Xbox Game Bar with Win+Alt+R), upload to YouTube as **Unlisted**, and embed it on the Summary page.

**Before recording, open these tabs:** the website (Summary page), the live site (signed in), CloudWatch dashboard `kape-lumen` (1-day view), CloudWatch Alarms, the S3 bucket `backups/`, an EC2 Session Manager terminal, GitHub Actions "Deploy to AWS", and Gmail with the alarm and nightly-check emails.

**Tips:** say it in your own words, not word for word. Keep each part to its time. If the restore takes a moment, keep talking about what it is checking.

---

## 0:00–0:45 · Summary (website Summary page)
- "I'm Renzo. This is Kapé Lumen, a virtual barista for a fictional café, built on LibreChat, the open-source chat app, MIT licence."
- "The brief is about operations, not the AI: I deployed it to AWS and ran it properly: monitoring, backups, security and automation."
- Scroll to **What improved**: "Before: no backups, no monitoring, eight security problems, and the bare model got 1 of 10 café questions right. After: restore in 13 seconds, alerts within about 3 minutes, no open security problems, 10 out of 10."

## 0:45–1:45 · The reskin and the live system
- Show the **System** page's before/after screenshots for a second, then switch to the **live site** `https://47-131-78-149.sslip.io`.
- Point at the padlock: "This is the real deployment on AWS, over HTTPS."
- Ask: **"How much is an iced Spanish latte?"** → ₱170. "It answers only from the café's own documents, stored in S3."
- Ask: **"I have celiac disease. Is the flourless chocolate cake safe for me?"** → it refuses and sends you to the staff. "It is not allowed to give allergy advice."

## 1:45–2:30 · Infrastructure (website Infrastructure page)
- On the diagram, follow the red path: "Browser to Caddy for HTTPS, to LibreChat, to my gateway, which adds the café documents from S3 and the key from Parameter Store, then calls Gemini outside AWS."
- "One t3.small server in Singapore. Deliberately one server: cheap and simple. The trade-off is that it is a single point of failure, which my Well-Architected review names as the first gap to fix."

## 2:30–3:45 · Monitoring and alarms
- **CloudWatch dashboard**: "Top row is what customers feel: is it up, are answers working, how fast. Middle is the server. Bottom is the nightly jobs."
- **Alarms list**: "Ten alarms. For example, failing answers fires on 3 failures in 5 minutes, because the site can be up while every answer fails."
- **Gmail**: open the `kape-answers-failing` email. "I tested the whole path: the alarm emailed me on 7 November at 04:21 UTC."
- Optional, 10 s: show one `chat_request` line in `/kape/gateway`: "Every question is logged with how long it took, whether it worked, and which version answered."

## 3:45–4:45 · Backup and a live restore
- **S3 `backups/`**: "Every night at 2 a.m. the database and uploads go to S3, kept 14 days, with counts and checksums."
- **Session Manager**, run:
  `sudo /opt/kape/app/infra/ops/restore.sh --test latest`
- While it runs: "This restores the newest backup into a separate test database, so customers are not affected, and checks every collection's count against the backup."
- When it prints **OK in ~13 s**: "That is the restore working. It also runs by itself every Sunday."

## 4:45–6:00 · The incident (website Automation & incident page)
- "My first restore test on AWS was killed with exit code 137. 137 means killed, so on a 2 GB server I assumed it ran out of memory, and I made a quick workaround that got the test passing in 3 minutes."
- "But I didn't stop there. The kernel log showed no out-of-memory kill. MongoDB's own log said **Too many open files**." Show the log block on the page.
- "MongoDB keeps a file per collection and per index; the restore test makes a second copy of all of them, and Docker's default limit is 1024. MongoDB crashed, Docker restarted it, and that killed the restore."
- "The fix was raising the limit to 64000; here it is on the server, and the restore passing afterwards." Show the two screenshots.
- "Time to detect: under a minute. Time to fix: 3 minutes. The lesson: read the failing service's own log before guessing."

## 6:00–6:40 · Automation
- **Gmail**: the "nightly check: 100% correct" email. "Every night at 2:30 it asks the ten test questions and emails me the score."
- **GitHub Actions**: "And every push to main is tested and deployed automatically. GitHub signs in to AWS without any stored keys. The first six runs failed while I set it up, and I kept them as evidence."
- If you have them by then: show the **Unattended runs** table: "These ran with nobody touching them."

## 6:40–7:15 · Results and next steps
- **Results** page bar chart: "Same ten questions, same model: 1 of 10 without the café's documents, 10 of 10 with them. And my checker has a flaw: one 'wrong' answer was actually safe."
- **Next steps**: "First, daily disk snapshots, so a dead server is minutes to rebuild instead of half an hour. Then failing fast when the free model quota runs out."
- "Thank you."

---

**After recording:** check that no password or key appears on screen (the Session Manager terminal and the sign-in page are the usual places). Upload as Unlisted, then replace the TODO on `site/index.html` with:
```html
<iframe width="100%" height="460" src="https://www.youtube-nocookie.com/embed/VIDEO_ID" title="Kapé Lumen presentation" allowfullscreen></iframe>
```
