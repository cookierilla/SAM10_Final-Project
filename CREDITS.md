# Credits and Licences

## Base system: LibreChat
- **Project:** LibreChat, an open-source ChatGPT-style chat application
- **Source URL:** https://github.com/danny-avila/LibreChat
- **Author:** Danny Avila and the LibreChat contributors
- **Licence:** MIT, https://github.com/danny-avila/LibreChat/blob/main/LICENSE
- **Version used:** _TODO: record the release tag or commit you cloned (`git -C vendor/LibreChat describe --tags`)_
- **What it did originally:** A general-purpose chat interface for many AI providers (OpenAI, Anthropic, Google, etc.), with user accounts and saved conversations.
- **What we changed:** See the System Card on the project website (reskin table).

The MIT licence allows modification and redistribution, provided the copyright notice and licence text are kept. The original `LICENSE` file stays inside the LibreChat source we deploy.

## AI model: Google Gemini (free tier)
- **Provider:** Google AI Studio / Gemini API, https://ai.google.dev/
- **Model:** _TODO: record the exact model ID (e.g. the Flash model you choose)_
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
