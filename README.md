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
_TODO (week 4)._

## Secrets
No keys, passwords or tokens are stored in this repository. Locally they live in a gitignored `.env`. On AWS they live in SSM Parameter Store (SecureString) and are read at runtime. Run `gitleaks detect` before every push.

## Contribution log (solo)
| Week | Dates | What I did | Evidence |
|---|---|---|---|
| 1 | 2026-11-06 – | Read the brief, chose domain (café) and model (Gemini free tier). Created the repo, wrote invented café content and 10 test questions. Built brew-gateway (S3/SSM-ready proxy with request logging and 6 tests), the LibreChat reskin config, and the local install script. | commits, `npm test` output |
| 2 | 2026-11-06 – | Prepared the AWS deployment before creating the account: production compose file (Caddy HTTPS, Mongo auth, pinned LibreChat image), EC2 bootstrap, secrets in SSM, least-privilege IAM policies, CloudWatch agent config, deploy runbook, website skeleton + Pages workflow. | commits |
| 3 | | | |
| 4 | | | |
| 5 | | | |
