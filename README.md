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
| `infra/` | Bootstrap script, Caddyfile, CloudWatch agent config, IAM policies, `.env.example` |
| `automation/` | Nightly backup and nightly test-question job |
| `eval/` | Labelled test questions and the scoring script |
| `site/` | Project website (GitHub Pages) |
| `docs/` | Setup guides and evidence screenshots |

## Getting started locally
See [docs/SETUP-LOCAL.md](docs/SETUP-LOCAL.md).

## How to deploy
_TODO (week 2): step-by-step AWS deployment._

## How to deploy the automations
_TODO (week 4)._

## Secrets
No keys, passwords or tokens are stored in this repository. Locally they live in a gitignored `.env`. On AWS they live in SSM Parameter Store (SecureString) and are read at runtime. Run `gitleaks detect` before every push.

## Contribution log (solo)
| Week | Dates | What I did | Evidence |
|---|---|---|---|
| 1 | 2026-11-06 – | Read the brief, chose domain (café) and model (Gemini free tier). Created the repo, wrote invented café content and 10 test questions. Built brew-gateway (S3/SSM-ready proxy with request logging and 6 tests), the LibreChat reskin config, and the local install script. | commits, `npm test` output |
| 2 | | | |
| 3 | | | |
| 4 | | | |
| 5 | | | |
