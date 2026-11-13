# Evidence index

Evidence IDs follow Appendix B of the SAM10 brief. Each item will be embedded on the project website next to the claim it supports, with the caption below. All screenshots are of the **local** stack (http://localhost:3080) on 2026-11-06, unless stated. Every file was checked for keys, passwords and personal data (none; all accounts are invented).

| ID | File | Caption (draft) |
|---|---|---|
| E-01 | `E-01-kape-login.png` | Kapé Lumen login page: our logo, cream-and-coffee theme, privacy and terms links. |
| E-01 | `E-01-kape-terms-modal.png` | The terms pop-up every user must accept: invented café, no allergy advice, no personal data. |
| E-01 | `E-01-kape-welcome.png` | New chat: one fixed assistant, "Lumen · Virtual Barista"; LibreChat's other models and tools are hidden. |
| E-01 / E-03 test 1 | `E-01-kape-chat-spanish-latte.png` | "How much is an iced Spanish latte?" → ₱170, matching `content/menu.md`. (Model: gemini-3.5-flash.) |
| E-01 | `E-05-reskinned-chat.png` | Reskinned chat (taken by me). |
| E-03 test 2 | `E-03-test2-celiac-refusal.png` | Safety test: a celiac customer asks if a cake is safe. Lumen correctly refuses and sends them to the staff. (Model: gemini-3.5-flash-lite.) |
| E-03 test 3 (failure) | `E-03-test3-FAILURE-gemini-daily-quota-429.png` | **Failure:** the same question during testing returned "The provider declined this request…". Cause: Gemini's free tier allows only 20 requests/day for gemini-3.5-flash, and testing used them up (gateway log in E-09). Fix: switched to gemini-3.5-flash-lite and turned off auto chat titles to halve calls. |
| E-04 | `E-04-eval-2026-11-06-flash-lite.json` | `eval/run-eval.mjs` on the 10 starter questions: **10/10 correct** on gemini-3.5-flash-lite (2026-11-06 13:10 UTC). The questions are easy; the 30-question set will be harder. |
| E-05 | `E-05-original-login.png`, `E-05-original-register.png`, `E-05-original-chat.png`, `E-05-original-model-menu.png` | Stock LibreChat v0.8.9-rc1 before the reskin: LibreChat logo, green theme, many models and tools. |
| E-09 | `E-09-request-log-sample.jsonl` | brew-gateway request log: one JSON line per question with duration, success, HTTP status, gateway/content/model versions, plus a real 429 "per day" quota error. |
| E-15 | `E-15-fault-model-404-gateway-log.jsonl` | Fault, first run: every request returned 404 "gemini-2.5-flash is no longer available to new users". Fixed by changing `GEMINI_MODEL`. Candidate for the WS-F incident write-up. |

## AWS evidence (2026-11-07, region ap-southeast-1)
Screenshots are published unblurred by choice: they show the AWS account number and the owner's email, but no keys, tokens or passwords (checked).

| ID | File | Caption | On the website |
|---|---|---|---|
| E-02 | `E-02-ec2-instance.png`, `E-02-live-url-chat.png` | The t3.small instance; Lumen answering at the public HTTPS address. | System |
| E-04 | `E-04-eval-before-no-cafe-data.json` | "Before": the same 10 questions sent to the same model with no café data: 1/10 (2026-11-07 15:04 UTC). | Results |
| E-06 | `E-06-dashboard.png`, `E-06-dashboard-1w.png` | The `kape-lumen` CloudWatch dashboard; the same over one week (2026-11-06 to 11-13). | Monitoring |
| E-07 | `E-07-alarms-list.png` | The ten `kape-` alarms. | Monitoring |
| E-08 | `E-08-sns-subscription-confirmed.png`, `E-08-alarm-email.png` | Confirmed SNS email subscription; alarm email received 2026-11-07 04:21:05 UTC. | Monitoring |
| E-09 | `E-09-log-groups-retention.png` | `/kape/*` log groups with 14-day retention. | Monitoring |
| E-10 | `E-10-backup-run.png`, `E-10-backup-in-s3.png`, `E-10-s3-versioning.png` | First backup on AWS (04:14:53 UTC), its files in S3, versioning on. | Backup |
| E-11 | `E-11-restore-test.png` | Restore test killed with exit 137, then passing (14 s). | Backup, Incident |
| E-12 | `E-12-root-mfa.png`, `E-12-iam-users.png`, `E-12-iam-user-permissions.png`, `E-12-admin-role-mfa-trust.png`, `E-12-cli-user-and-role.png`, `E-12-ec2-role-least-privilege.png`, `E-12-security-group-no-ssh.png`, `E-12-cloudtrail.png`, `E-12-ebs-encrypted.png` | MFA, IAM users and roles, least privilege, no SSH, CloudTrail, encrypted disk. | Security |
| E-13 | `E-13-parameter-store.png` | Secrets in Parameter Store (names only). | Security |
| E-14 | `E-14-eval-email.png`, `E-14-github-deploy-run.png`, `E-14-unattended-runs.png` | Nightly check email (10/10); GitHub Actions deploy run #7 green; Logs Insights showing the first unattended backup, quality check and Sunday restore test (2026-11-07 UTC). | Automation, Incident |
| E-15 | `E-15-oom-evidence.png`, `E-15-mongo-too-many-open-files.txt`, `E-15-ulimit-fixed.png`, `E-15-restore-after-fix.png` | Incident: no OOM kill, MongoDB's "Too many open files" crash, limit raised to 64000, restore passing after the fix. | Incident |
| E-16 | `E-16-billing-alerts-enabled.png`, `E-16-budget-alert.png`, `E-16-cost-baseline-day0.png`, `E-16-cost-2026-11-12.png`, `E-16-results-graph.png` | Billing alerts on; $10 budget alert; cost $0.00 for 2026-11-01 to 11-08; usage vs credits to 11-12 ($0.84/day usage, $0.00 billed); dashboard for 2026-11-08 to 11-13 (100% up, 0 failed, slow nights). | Security, Results |
| E-18 | `site/assets/infrastructure.svg` | Infrastructure diagram. | Infrastructure |

## Still to capture
Optional `E-17-well-architected-report.pdf`.
