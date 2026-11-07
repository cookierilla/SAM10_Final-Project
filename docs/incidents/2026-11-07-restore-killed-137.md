# Incident 2026-11-07: restore test killed (exit 137)

**Status:** fixed · **Severity:** high for recovery (no tested restore), none for customers (the live site was not affected)

## What happened
The first restore test on AWS (`restore.sh --test latest`) stopped after 8 seconds with
`FAILED (test): line 88 exited with status 137`. Line 88 is the `mongorestore` command.
Exit status 137 = 128 + 9: the process was **killed with SIGKILL**. It did not fail by itself.
Until this was fixed we had backups, but no proof that we could restore them.

## Timeline (UTC; PHT = UTC+8)
| Time | Event |
|---|---|
| 04:14:53 | First backup on AWS succeeds (`20261107T041453Z`, 14 221 bytes) |
| 04:17:08 | Restore test started by hand |
| 04:17:16 | **Fault starts and is noticed:** restore killed, exit 137 |
| 04:18–04:19 | Investigation: `free -m` shows 1905 MB total, 937 MB available, 224 MB of swap in use |
| 04:19:19 | Fix committed (`a4acc00`): restore one collection at a time |
| 04:20:10 | Restore test passes: all counts match, 14 s |

**Time to detect:** under 1 minute (the job was being watched; at night the same failure emails `kape-alerts` and sets `RestoreTestSuccess = 0`).
**Time to fix:** 3 minutes from failure to a passing restore.

## Root cause
_Still being confirmed. Do not claim more than the evidence shows._

**Evidence so far (collected 2026-11-07):**
- `journalctl -k` for 04:16–04:19 shows **no** OOM-killer messages: the kernel did not kill anything for lack of memory.
- `docker inspect chat-mongodb`: `restarts=1 started=2026-11-07T04:17:16.84Z oomkilled=false`. MongoDB's container **restarted at the exact second the restore failed**.

So it was not `mongorestore` that ran out of memory. **`mongod` itself exited**, Docker restarted it (`restart: always`), and that killed the `mongorestore` running inside the container, hence 137. Why mongod exited is in its own log (CloudWatch `/kape/mongo`, just before 04:17:16).

Working hypothesis: the instance has 2 GB of RAM, already about half used by LibreChat (Node), MongoDB and the gateway. By default `mongorestore` restores **4 collections in parallel**, and this database has about 60 collections, each with indexes to rebuild. That parallel load pushed memory over the limit, so the Linux **out-of-memory (OOM) killer** ended a process. Either `mongorestore` itself was killed, or `mongod` was, which takes down the restore running inside its container.

## Evidence to collect (Session Manager, then save the output)
```bash
# 1. Did the kernel's OOM killer act at 04:17, and which process did it kill?
sudo journalctl -k --since "2026-11-07 04:16" --until "2026-11-07 04:19" | grep -iE "out of memory|oom-kill|killed process"
# 2. Did MongoDB's container get killed and restarted?
sudo docker inspect chat-mongodb --format 'restarts={{.RestartCount}} started={{.State.StartedAt}} oomkilled={{.State.OOMKilled}}'
# 3. Memory now, for comparison
free -m; sudo docker stats --no-stream --format 'table {{.Name}}\t{{.MemUsage}}'
```
Save the output as `docs/evidence/E-15-oom-kernel-log.txt`, after checking it contains no secrets.

## The change that stops it happening again
1. `restore.sh` runs `mongorestore --numParallelCollections=1 --numInsertionWorkersPerCollection=1`, so it restores one collection at a time with less memory in use at once (commit `a4acc00`).
2. Detection is automatic: the restore test runs **every Sunday unattended**. Any failure emails `kape-alerts` and publishes `RestoreTestSuccess = 0` (dashboard). `kape-memory-high` alarms if memory stays above 85%.
3. The runbook (`docs/runbooks/restore-from-backup.md`) lists exit 137 under Gotchas.

## Evidence the change worked
- 04:20:10: the same backup restored with all counts matching (`E-11-restore-test.png`).
- _Add:_ the unattended Sunday restore tests (timestamps from `/kape/host`, stream `*/automation`).

## What we learned
- A 2 GB server has little headroom: one-off heavy jobs need limits, not defaults.
- Editing a script directly on the server got the restore working but blocked the next deploy. Fixes go through the repo. `deploy.sh` now says so when it happens.
