# Credits and Licences

## Base system: LibreChat
- **Project:** LibreChat, an open-source ChatGPT-style chat application
- **Source URL:** https://github.com/danny-avila/LibreChat
- **Author:** Danny Avila and the LibreChat contributors
- **Licence:** MIT, https://github.com/danny-avila/LibreChat/blob/main/LICENSE
- **Version used:** `v0.8.9-rc1-84-gf4154b649` (commit `f4154b649efa37e1345ccc517a4d8d1ed2178c82`, 2026-10-31), Docker image `registry.librechat.ai/librechat-ai/librechat-dev:latest`
- **What it did originally:** A general-purpose chat interface for many AI providers (OpenAI, Anthropic, Google, etc.), with user accounts and saved conversations.
- **What we changed:** See the System Card on the project website (reskin table).

The MIT licence allows modification and redistribution, provided the copyright notice and licence text are kept. The original `LICENSE` file stays inside the LibreChat source we deploy.

## AI model: Google Gemini (free tier)
- **Provider:** Google AI Studio / Gemini API, https://ai.google.dev/
- **Model:** `gemini-3.5-flash-lite` via the OpenAI-compatible endpoint. History (2026-11-06): `gemini-2.5-flash` returned 404 (retired for new keys); `gemini-3.5-flash` worked but its free tier allows only 5 requests/minute and 20 requests/day, used up within an hour of testing; switched to the lite model.
- **Terms:** Gemini API Additional Terms of Service, https://ai.google.dev/gemini-api/terms
- **Note:** On the free tier, Google may use prompts to improve its products. That is one more reason the assistant only ever receives **invented** café data, never personal data.

## Content
All café content in `content/` (Kapé Lumen, its menu, branches, people and policies) is **invented** for this project. Any resemblance to a real business is unintended.

## Other tools
- Caddy web server (Apache-2.0), https://caddyserver.com/
- MongoDB Community Server (SSPL), used unmodified as LibreChat's database
- _Add any tutorial, AWS doc or re:Post article you rely on here, with its URL._

## AI assistance declaration (draft; keep updated)
Claude (Anthropic) was used to help plan the project, scaffold the repository, draft invented café content and explain configuration. Every output was reviewed, tested on the running system, and changed where needed by the student.
