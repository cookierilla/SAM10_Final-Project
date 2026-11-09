# Presentation video: script and shot list

**Target length: 7 minutes. The limit is 5 to 8.** The brief asks for a live demonstration of the reskin, the deployed system on AWS, the dashboard and alarms, the restore and the fault, in the same order as the website. Each section below has two columns: **Show** is what is on screen, and **Say** is what you say while it is there. Say it in your own words; you don't have to read it out word for word.

---

## 1. Before you record (about 15 minutes)

### Open these tabs, in this order, in one browser window
Put the tabs in this order so you can go left to right with Ctrl+Tab while recording.

| # | Tab | How to get it ready |
|---|---|---|
| 1 | **Your website: Summary page** | `https://cookierilla.github.io/SAM10_Final-Project/` (push first so it has the latest pages). Zoom the browser to 110% so text is readable. |
| 2 | **Live site, signed in** | `https://47-131-78-149.sslip.io`. **Sign in before you record**, so your password is never on screen. Start a new chat and leave it empty. |
| 3 | **CloudWatch dashboard** | CloudWatch → Dashboards → `kape-lumen`, time range **1w** (or 3d). |
| 4 | **CloudWatch Alarms** | CloudWatch → Alarms → All alarms, so all ten `kape-` alarms are listed, all **OK**. |
| 5 | **S3 backups** | S3 → `kape-lumen-content-590132201925` → `backups/`, sorted newest first. |
| 6 | **Session Manager terminal** | EC2 → Instances → `i-02997110be86be86b` → Connect → Session Manager → Connect. Type `sudo -i` then `clear`, so the screen is empty. Don't run anything else yet. |
| 7 | **Gmail: alarm email** | Search `kape-answers-failing`, open the ALARM email from 7 Nov (04:21 UTC). Opening the email hides the rest of your inbox. |
| 8 | **Gmail: nightly check email** | In a second Gmail tab, search `Kape Lumen nightly check` and open the newest one. |
| 9 | **GitHub Actions** | Your repo → Actions → "Deploy to AWS", so the list of runs (#1–#7 and later) shows. |

### Check before you press record
- [ ] Close every other tab and notification (Windows: turn on **Do not disturb**). Don't open Parameter Store or any `.env` file on camera.
- [ ] The Session Manager tab will time out after about 20 minutes idle. If it does, reconnect just before you record.
- [ ] Practise section 5 (the restore) once off camera, so you know it takes about 15 seconds.
- [ ] Microphone: speak a test sentence and play it back.

### How to record
**Easiest: Xbox Game Bar** (built into Windows). It records one app window, and everything here is in one browser window.
1. Press **Win+G**. In the **Capture** widget, click the microphone icon so it is **on**. (Or press **Win+Alt+M** during recording.)
2. Click inside the browser, then press **Win+Alt+R** to start. Press **Win+Alt+R** again to stop.
3. The video goes to `C:\Users\edzle\Videos\Captures`.

**If you want your face in a corner** (the brief says "you presenting"; voice alone is usually accepted, but a webcam is safer): use **OBS Studio** (free). Add a *Window Capture* of the browser, a *Video Capture Device* for your webcam (shrink it into a corner), and your microphone, then click **Start Recording**.

**If you stumble:** pause for two seconds and say the sentence again. You can cut the mistake later with the Windows **Clipchamp** or Photos editor, or just re-record that section and join them.

---

## 2. Script

### 0:00–0:45 · Summary (tab 1, website Summary page)
| Show | Say |
|---|---|
| Top of the Summary page | "Hi, I'm Renzo. This is Kapé Lumen, a virtual barista for a fictional café. It's built on LibreChat, an open-source chat app under the MIT licence." |
| Scroll slowly through "What the system does" | "Customers ask everyday questions like prices, opening hours and the loyalty card, and it answers only from the café's own documents. It won't give allergy or medical advice." |
| Stop on the **What improved** table and point at each row with the mouse | "The project is about running it properly. Before: no backups, no monitoring, eight security problems, and the bare model got 1 of 10 café questions right. After: a restore in 13 seconds, an alert within about 3 minutes, no open security problems, and 10 out of 10." |

### 0:45–1:45 · The reskin and the live system (tab 2, live site)
| Show | Say |
|---|---|
| On the website, click **System** and point at the before/after reskin screenshots for a moment, then switch to tab 2 | "This is the reskin: new name, logo, colours and wording, and one fixed assistant instead of a list of AI models." |
| Point at the padlock and the address bar | "And this is the real deployment on AWS in Singapore, over HTTPS." |
| Type **How much is an iced Spanish latte?** and send. Wait for the answer (₱170). | "It answers from the café's menu, which is stored in Amazon S3, not built into the model." |
| Type **I have celiac disease. Is the flourless chocolate cake safe for me?** and send. | "And for allergy questions it refuses and sends you to the staff, because guessing could hurt someone." |

### 1:45–2:30 · Infrastructure (tab 1, website Infrastructure page)
| Show | Say |
|---|---|
| Click **Infrastructure**. Trace the path on the diagram with the mouse from the browser icon onwards. | "A question goes from the browser to Caddy, which handles HTTPS, to LibreChat, to my small gateway. The gateway adds the café documents from S3 and the AI key from Parameter Store, then calls Google Gemini, which is outside AWS." |
| Point at the EC2 box | "Everything runs on one t3.small server. That's deliberate: cheap and simple. The trade-off is a single point of failure, and my Well-Architected review names that as the first gap to fix." |

### 2:30–3:45 · Monitoring and alarms (tabs 3, 4, 7)
| Show | Say |
|---|---|
| Tab 3, dashboard. Point at the top row. | "This is my CloudWatch dashboard. The top row is what customers feel: is the site up, are answers working, how fast are they." |
| Point at the middle row, then the bottom row | "The middle row is the server: CPU, memory, disk. The bottom row is the nightly jobs: backups, the restore test and the quality check." |
| Tab 4, alarm list. Scroll through all ten. | "There are ten alarms. For example, failing answers fires on 3 failures in 5 minutes, because the site can be up while every answer fails." |
| Tab 7, the alarm email | "I tested the whole path on purpose: the alarm went off and emailed me on 7 November at 04:21 UTC." |

### 3:45–4:45 · Backup and a live restore (tabs 5, 6)
| Show | Say |
|---|---|
| Tab 5, S3 `backups/`. Point at the dated folders. | "Every night at 2 a.m. the database and uploaded files are backed up to S3, kept for 14 days, with counts and checksums." |
| Tab 6, Session Manager. Type `/opt/kape/app/infra/ops/restore.sh --test latest` and press Enter. | "Now I'll restore last night's backup, live." |
| While it runs (about 15 s) | "It restores the newest backup into a separate test database, so customers aren't affected, and checks every collection's document count against the backup." |
| When it prints **OK** | "That's it: restored and checked in about 14 seconds. It also runs by itself every Sunday at 3:30 in the morning, and the first unattended run passed." |

### 4:45–6:00 · The incident (tab 1, website Automation & incident page)
| Show | Say |
|---|---|
| Click **Automation & incident**, scroll to the **Incident** heading | "Here's the real fault. My first restore test on AWS was killed with exit code 137." |
| Point at the E-11 screenshot | "137 means 'killed'. On a 2 GB server I assumed it ran out of memory, so I made a quick workaround, and the test passed three minutes later." |
| Point at the E-15 screenshot (kernel log, `oomkilled=false`) | "But I didn't stop there. The kernel log had no out-of-memory kill, and Docker said the container wasn't killed for memory." |
| Point at the MongoDB log block, especially **Too many open files** | "MongoDB's own log had the answer: Too many open files. MongoDB keeps a file per collection and per index, and the restore test makes a second copy of all of them. Docker's default limit is 1024. MongoDB crashed, Docker restarted it, and that killed the restore." |
| Point at the two "fix" screenshots | "The fix was raising the limit to 64000, MongoDB's recommended minimum. Here it is on the server, and here's the restore passing afterwards." |
| Point at the summary box at the top of the section | "Time to detect: under a minute. Time to fix: three minutes. And the lesson: read the failing service's own log before guessing." |

### 6:00–6:40 · Automation (tabs 1, 8, 9)
| Show | Say |
|---|---|
| Scroll up the same page to the **Unattended runs** table | "These ran with nobody touching anything: the nightly backup, the quality check and the Sunday restore test, from the automation log in CloudWatch." |
| Tab 8, nightly check email | "Every night at 2:30 the system asks itself the ten test questions and emails me the score. Last night: 10 out of 10." |
| Tab 9, GitHub Actions | "And every push to the main branch is tested and deployed automatically. GitHub signs in to AWS without any stored keys. The first six runs failed while I set it up, and I kept them as evidence." |

### 6:40–7:15 · Results and next steps (tab 1, website Results and Next steps pages)
| Show | Say |
|---|---|
| Click **Results**, point at the bar chart | "Same ten questions, same model: 1 out of 10 without the café's documents, 10 out of 10 with them. And my checker isn't perfect: one 'wrong' answer was actually safe." |
| Click **Next steps**, point at item 1 | "Next, I'd add daily disk snapshots, so a dead server takes minutes to rebuild instead of half an hour, and then make answers fail fast when the free AI quota runs out." |
| Back to the Summary page | "That's Kapé Lumen. Thank you." |

---

## 3. After recording
1. **Watch it once all the way through** and check:
   - no password, key or token appears anywhere, especially in the terminal and on the sign-in page;
   - it's between 5 and 8 minutes;
   - your voice is clear.
2. **Upload to YouTube.** Go to YouTube Studio → Create → Upload. Title: *Kapé Lumen — SAM10 Final Project*. Set visibility to **Unlisted**, not Private: Private videos won't play on your website.
3. **Send me the link.** I'll replace the TODO on `site/index.html` with:
   ```html
   <iframe width="100%" height="460" src="https://www.youtube-nocookie.com/embed/VIDEO_ID" title="Kapé Lumen presentation" allowfullscreen></iframe>
   ```
