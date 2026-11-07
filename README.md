# Kapé Lumen Assistant (SAM10 Final Project)

A virtual barista for **Kapé Lumen**, a fictional café. It answers questions about the menu, branches, opening hours, loyalty card and house policies. It is a reskin of [LibreChat](https://github.com/danny-avila/LibreChat) (MIT), deployed on AWS and operated with monitoring, backups, security controls and automation.

> Course: SAM10 Systems Administration and Maintenance · Solo project · All data invented.

## Architecture (planned)
```
User ─HTTPS─> EC2 (Caddy) ─> LibreChat ─> brew-gateway ─> Google Gemini API
                               │              ├─ café docs from S3 (versioned)
                               └─ MongoDB     ├─ API key from SSM Parameter Store
                                              └─ JSON request logs + metrics -> CloudWatch -> SNS email
```

## Repository layout
| Folder | What is in it |
|---|---|
| `content/` | Invented café knowledge base (synced to S3) |
| `librechat/` | Our LibreChat config: `librechat.yaml`, compose override, branding assets |
| `gateway/` | brew-gateway: small Node service between LibreChat and Gemini |
| `infra/` | Production stack: `docker-compose.yml`, Caddyfile, EC2 bootstrap and deploy scripts, secrets/content scripts, CloudWatch agent config, IAM policies |
| `automation/` | Nightly backup and nightly test-question job |
| `eval/` | Labelled test questions and the scoring script |
| `site/` | Project website, published to GitHub Pages by `.github/workflows/pages.yml` |
| `docs/` | Setup guides and evidence screenshots |

## Getting started locally
See [docs/SETUP-LOCAL.md](docs/SETUP-LOCAL.md).

## How to deploy
See [docs/DEPLOY-AWS.md](docs/DEPLOY-AWS.md): account safety, CLI setup, S3 + Parameter Store, IAM role, security group, launch and verify. After the first launch, redeploy with `infra/deploy.sh` on the instance (via Session Manager or `aws ssm send-command`).

## Website
Edit `site/*.html` and push: GitHub Actions publishes it (one-time: repo **Settings → Pages → Source: GitHub Actions**). Preview locally with `python -m http.server 8765 --directory site` after copying `docs/evidence/*.png` into `site/evidence/`.

## How to deploy the automations
All scheduled jobs live in this repo and are installed by `infra/deploy.sh` (cron file `infra/cron/kape-lumen`). Every deploy reinstalls them, so a push to `main` updates them too. Times are PHT.

| Job | When | Script | Proof it ran |
|---|---|---|---|
| Nightly backup to S3 | 02:00 daily | `infra/ops/backup.sh` | metric `BackupSuccess`, alarm `kape-backup-missing`, S3 `backups/<time>/` |
| Nightly quality check (emails the pass rate) | 02:30 daily | `infra/ops/eval.sh` | email, metric `EvalPassRate` |
| Restore test | 03:30 Sundays | `infra/ops/restore.sh --test latest` | metric `RestoreTestSuccess` |
| Site check | every minute | `infra/ops/probe.sh` | metric `SiteUp`, alarm `kape-site-down` |
| Deploy on push to `main` | on push | `.github/workflows/deploy.yml` | GitHub Actions run history |

Setup: [docs/DEPLOY-AWS.md](docs/DEPLOY-AWS.md) Parts G and H. Alarms and dashboard: `infra/monitoring/setup-monitoring.sh`. Every job logs to `/var/log/kape-automation.log`, which is shipped to CloudWatch `/kape/host`.

Runbook: [docs/runbooks/restore-from-backup.md](docs/runbooks/restore-from-backup.md). Incident: [docs/incidents/2026-11-07-restore-killed-137.md](docs/incidents/2026-11-07-restore-killed-137.md).

## Secrets
No keys, passwords or tokens are stored in this repository. Locally they live in a gitignored `.env`. On AWS they live in SSM Parameter Store (SecureString) and are read at runtime. Run `gitleaks detect` before every push.

## Contribution log (solo)
| Phase | Date | What I did | Evidence |
|---|---|---|---|
| Local build and reskin | 2026-11-06 | Read the brief, chose domain (café) and model (Gemini free tier). Created the repo, wrote invented café content and 10 test questions. Built brew-gateway (S3/SSM-ready proxy with request logging and tests), the LibreChat reskin config, and the local install script. Eval: 10/10. | E-01, E-03, E-04, E-05 |
| AWS preparation | 2026-11-06 | Wrote the AWS deployment before creating the account: production compose file (Caddy HTTPS, Mongo auth, pinned LibreChat image), EC2 bootstrap, secrets in SSM, least-privilege IAM policies, CloudWatch agent config, deploy runbook, website skeleton + Pages workflow. | commits |
| Account safety | 2026-11-06 | Root MFA, $10 budget alert, MFA-protected admin role, read-only IAM user with MFA, CLI through the role, CloudTrail. | E-12, E-16 |
| Deployment | 2026-11-07 | S3 bucket (versioned), secrets in Parameter Store, log groups with 14-day retention, SNS alerts, least-privilege EC2 role, HTTP/HTTPS-only security group. Launched t3.small; fixed two first-boot issues found in review. Live over HTTPS. | E-02, E-08, E-09, E-10, E-12, E-13 |
| Monitoring and backups | | | |
| Automations and incident | | | |
| Website and video | | | |
