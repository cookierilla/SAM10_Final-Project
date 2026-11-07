# Incident 2026-11-07: restore test killed (exit 137): MongoDB ran out of file handles

**Status:** fixed · **Severity:** high for recovery (no tested restore); low for customers (the live database restarted, unavailable for about 3 seconds)

## What happened
The first restore test on AWS (`restore.sh --test latest`) stopped after 8 seconds with
`FAILED (test): line 88 exited with status 137`. Line 88 is the `mongorestore` command.
Exit status 137 = 128 + 9: the process was **killed with SIGKILL**. It did not fail by itself.
Until this was fixed we had backups, but no proof that we could restore them.

## Timeline (UTC; PHT = UTC+8)
| Time | Event |
|---|---|
| 04:14:53 | First backup on AWS succeeds (`20261107T041453Z`, 14 221 bytes) |
| 04:17:08 | Restore test started by hand. It restores a second copy of the database (`LibreChat_restoretest`), 4 collections at a time (default) |
| 04:17:16.000 | MongoDB log: `couldn't open [/proc/1/stat] Too many open files` |
| 04:17:16.144 | MongoDB log: WiredTiger `error 24: Too many open files`, then `WT_PANIC … the process must exit and restart`, `Fatal assertion`, `Got signal: 6 (Aborted)` |
| 04:17:16.84 | Docker restarts `chat-mongodb` (`restart: always`). The `mongorestore` running inside it dies with it: **exit 137** |
| 04:17:17.58 | MongoDB starting again; `Detected unclean shutdown`, recovers from the last checkpoint |
| 04:17:19 | MongoDB startup warning: `Soft rlimits for open file descriptors too low`, `currentValue: 1024`, `recommendedMinimum: 64000` |
| 04:18–04:19 | Investigation: `free -m` shows 1905 MB total, 937 MB available, 224 MB of swap in use. Memory was suspected first |
| 04:19:19 | Workaround committed (`a4acc00`): restore one collection at a time |
| 04:20:10 | Restore test passes: all counts match, 14 s |
| later the same day | Root cause found in `/kape/mongo` (above). Real fix: open-file limit raised to 64000 |

**Time to detect:** under 1 minute (the job was being watched; at night the same failure emails `kape-alerts` and sets `RestoreTestSuccess = 0`).
**Time to fix:** 3 minutes to a passing restore (workaround); root cause confirmed and fixed the same day.

## Root cause
**MongoDB hit the operating system's limit of 1024 open files and crashed.**

- MongoDB's storage engine (WiredTiger) keeps **one file per collection and one per index**. LibreChat's database has 60 collections, many with 5–12 indexes, so it already uses a few hundred files.
- The restore test creates a **second copy** of all of them (`LibreChat_restoretest`). The restore was running 4 collections and several index builds at the same time. File numbers in the log had reached `index-1070`.
- Docker starts containers with a limit of **1024 open files**. MongoDB recommends at least 64 000, and warns about it in its own startup log.
- When WiredTiger could not open one more file it panicked by design (`the process must exit and restart`). mongod aborted, Docker restarted it, and the `mongorestore` running inside the same container was killed: exit 137.

**What it was not (checked):**
- Not the kernel's out-of-memory killer: `journalctl -k` for 04:16–04:19 has no OOM messages.
- Not a container memory limit: `docker inspect chat-mongodb` shows `oomkilled=false`, with `restarts=1 started=2026-11-07T04:17:16.84Z`.

Our first guess (memory) was wrong. Restoring one collection at a time made the test pass because fewer files were open at once. It did not remove the cause: as the database grows, the same failure would come back.

**Customer impact:** the crashed mongod was the **live** database too. It was down from 04:17:16 to about 04:17:19. No alarm fired (too short for the 1-minute site check) and no data was lost (WiredTiger recovered from its checkpoint).

## The change that stops it happening again
1. **Fix:** `infra/docker-compose.yml` gives `chat-mongodb` an open-file limit of 64000 (`ulimits: nofile`), MongoDB's recommended minimum.
2. **Kept as a safety margin:** `restore.sh` still restores one collection at a time (`--numParallelCollections=1 --numInsertionWorkersPerCollection=1`, commit `a4acc00`).
3. **Detection is automatic:** the restore test runs **every Sunday unattended**. Any failure emails `kape-alerts` and publishes `RestoreTestSuccess = 0` (dashboard).
4. **The runbook** (`docs/runbooks/restore-from-backup.md`) lists exit 137 and "Too many open files" under Gotchas.

## Evidence
- `E-11-restore-test.png`: the failure (137) and the passing restore at 04:20:10.
- `E-15-oom-evidence.png`: no OOM-killer messages; `restarts=1`, `oomkilled=false`, restarted at 04:17:16.84.
- `E-15-mongo-too-many-open-files.txt`: the MongoDB log lines above (from CloudWatch `/kape/mongo`).
- `E-15-ulimit-fixed.png`: after the deploy, `Max open files 64000 64000` inside `chat-mongodb`.
- `E-15-restore-after-fix.png`: 14:23:52 UTC, restore test with the new limit: OK in 13 s, counts match.
- _Add:_ the unattended Sunday restore tests (timestamps from `/kape/host`, stream `*/automation`).

## What we learned
- **Read the failing service's own log before guessing.** Exit 137 and a small server pointed to memory; the MongoDB log said "Too many open files" in plain words.
- A workaround that makes the test pass is not the same as a root cause. We kept investigating after the test was green.
- Default limits (Docker's 1024 open files) are not production settings. Startup warnings in the logs are worth reading.
- Editing a script directly on the server got the restore working but blocked the next deploy. Fixes go through the repo, and `deploy.sh` now says so when it happens.
