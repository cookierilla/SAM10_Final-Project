# RUNBOOK: Restore Kapé Lumen from a backup

**Owner:** Renzo · **Last tested:** 2026-11-07 (test restore on AWS, 14 s) · **Takes:** about 5 minutes · **Ask:** Renzo

## 1. WHAT THIS IS FOR
Getting customers' accounts and chat history back after the database is lost, damaged or wrongly changed, using the nightly backup in S3.

## 2. HOW YOU KNOW YOU NEED IT
- `kape-site-down` or `kape-http-5xx` fired, and LibreChat's log (`/kape/librechat`) shows MongoDB errors; or
- a user reports their chats are gone or wrong; or
- `kape-backup-missing` fired, or the Sunday restore test emailed **"restore test FAILED"**. In that case go to Gotchas first.

Command that shows the problem (Session Manager on the instance):
```bash
sudo docker exec chat-mongodb sh -c 'mongosh --quiet -u "$MONGO_INITDB_ROOT_USERNAME" -p "$MONGO_INITDB_ROOT_PASSWORD" --authenticationDatabase admin --eval "db.getSiblingDB(\"LibreChat\").getCollectionNames().length"'
```
A healthy database prints about 60 (collections). An error or `0` means the data is missing.

## 3. WHAT IT AFFECTS
During a **live** restore, nobody can sign in or chat: LibreChat is stopped for the length of the restore (14 s for today's data). Anything written since the last backup (02:00 PHT) is lost. That gap is our RPO: up to 24 hours.

## 4. HOW TO DO IT
Connect: AWS console → EC2 → `kape-lumen` → **Connect → Session Manager → Connect**.

**Step 1.** See which backups exist:
```bash
aws s3 ls s3://$(sudo grep ^CONTENT_BUCKET= /opt/kape/.env | cut -d= -f2)/backups/
```
→ you should see one folder per night, e.g. `PRE 20261107T041453Z/`. Pick the newest one from **before** the problem started.

**Step 2.** Prove that backup is good, without touching the live site:
```bash
sudo /opt/kape/app/infra/ops/restore.sh --test 20261107T041453Z
```
→ you should see `expected counts: {...}`, then the identical `restored counts: {...}`, then `restore test of … OK`.

**Step 3.** Restore it for real:
```bash
sudo /opt/kape/app/infra/ops/restore.sh --live --yes 20261107T041453Z
```
→ you should see `stopping LibreChat`, the counts match, `started LibreChat again`, `restore live … OK`.

## 5. HOW TO CHECK IT WORKED
- [ ] the original symptom is gone: `curl -s https://47-131-78-149.sslip.io/health` prints `OK`
- [ ] sign in at https://47-131-78-149.sslip.io and ask **"How much is an iced Spanish latte?"**. The answer is ₱170.
- [ ] no new alarms for 10 minutes (CloudWatch → Alarms, or the `kape-lumen` dashboard)

## 6. HOW TO UNDO IT
The live restore keeps the replaced upload folders as `/opt/kape/data/librechat/{images,uploads}.before-restore-<time>`. To go back, move them back and restore a different (newer) backup with Step 3. The database you replaced is **not** kept, so if it might still be needed, run `sudo /opt/kape/app/infra/ops/backup.sh` **before** Step 3.

## 7. GOTCHAS
- **"FAILED (test): line … exited with status 137".** MongoDB crashed and restarted during the restore, killing `mongorestore` with it. On 2026-11-07 the cause was **"Too many open files"** (see the incident write-up). Check MongoDB's log: CloudWatch `/kape/mongo`, or `sudo docker logs --since 10m chat-mongodb 2>&1 | grep -E '"s":"(E|F)"'`. Check the open-file limit is 64000: `sudo docker exec chat-mongodb sh -c 'grep "open files" /proc/1/limits'`. If it shows 1024, redeploy (`infra/deploy.sh`), which applies the limit from `docker-compose.yml`.
- **"checksum mismatch: backup is damaged".** Don't use that backup. Pick the previous night's.
- **Never edit scripts on the server.** `deploy.sh` will then refuse to update (`git pull` fails). Fix the script in the repo and push. If the server already has a local edit: `sudo git -C /opt/kape/app checkout -- .`
- The bucket keeps backups for **14 days** (lifecycle rule). Older ones are gone.
- All times in folder names are **UTC**. 02:00 PHT is 18:00 UTC the day before.

## 8. CHANGE HISTORY
- 2026-11-07: first version. Tested on AWS: test restore OK in 14 s. Restore limited to one collection at a time after the 137 failure; the root cause (MongoDB's 1024 open-file limit) was fixed by raising it to 64000, re-tested OK in 13 s.
