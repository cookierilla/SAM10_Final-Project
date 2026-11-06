# Week 1: Run Kapé Lumen locally (Windows 10)

Goal for the end of week 1: LibreChat running on this PC with the Kapé Lumen reskin, answering from `content/` through brew-gateway. You also need screenshots of the **original** LibreChat UI (evidence E-05).

## 1. Install WSL2 and Docker Desktop (you do this; it needs admin rights and a reboot)
1. Open **PowerShell as Administrator** and run:
   ```powershell
   wsl --install
   ```
   Restart when it asks. After the restart, an Ubuntu window may open and ask for a username/password. Make one up (it's local to WSL).
2. Download Docker Desktop for Windows from https://www.docker.com/products/docker-desktop/ and install it. Keep **"Use WSL 2 instead of Hyper-V"** ticked.
3. Start Docker Desktop and wait until it says **Engine running**. Then check it in a new terminal:
   ```bash
   docker compose version
   ```

> Virtualization is already enabled in this PC's BIOS. If Docker still complains about WSL, run `wsl --update` as Administrator and restart Docker Desktop.

## 2. Get a Gemini API key
1. Go to https://aistudio.google.com/apikey and sign in with a personal Google account.
2. Click **Create API key** and copy it. Don't save it in any file in this project; the install script asks for it.
3. Note the free-tier rate limits for `gemini-2.5-flash` (or the model you pick) in AI Studio. You'll quote them in the system card.

## 3. Take the "original" screenshots first (E-05)
The brief wants the original LibreChat next to your reskin. The quickest way to get that is LibreChat's public demo, or a run of the stock app before our config is applied:
```bash
git clone https://github.com/danny-avila/LibreChat.git vendor/LibreChat
```
```bash
cd vendor/LibreChat && cp .env.example .env && docker compose up -d
```
Open http://localhost:3080, register a test account, and screenshot the login page and the chat screen. Save them in `docs/evidence/` as `E-05-original-login.png` and `E-05-original-chat.png`. Then stop it:
```bash
docker compose down
```

## 4. Install and start Kapé Lumen
From the project root, in PowerShell:
```powershell
.\librechat\install-local.ps1
```
The script:
- clones LibreChat into `vendor/LibreChat` (gitignored) if it isn't there yet and prints its version (copy that into `CREDITS.md`)
- copies our `docker-compose.override.yml` in, which adds the brew-gateway container and mounts `librechat.yaml` and the logo
- adds our settings to `vendor/LibreChat/.env`, generates `GATEWAY_TOKEN`, and asks for your Gemini key (input hidden)
- runs `docker compose up -d --build`

If you already ran step 3, delete the test account's data first so you start clean: `docker compose down -v` in `vendor/LibreChat`. Or just keep it.

## 5. Check it works
1. Open http://localhost:3080, accept the terms modal, and register with an invented name and email.
2. Ask: *"How much is an iced Spanish latte?"* The answer should be ₱170.
3. Ask: *"I have celiac disease, is the flourless cake safe?"* Lumen should refuse and send you to the staff.
4. Check the gateway's request log (one JSON line per question):
   ```bash
   docker logs brew-gateway --tail 5
   ```
5. Screenshot the reskinned chat (E-01).

## Things to check (I couldn't test these without Docker)
- **Logo:** the override mounts our logo at `/app/client/dist/assets/logo.svg`. If the old logo still shows, look for the real path inside the image:
  ```bash
  docker exec LibreChat sh -c "find /app/client -name 'logo.svg'"
  ```
  Then update the target path in `librechat/docker-compose.override.yml`.
- **Colours:** `interface.theme` in `librechat.yaml` only works on LibreChat builds newer than v0.8.8. If the colours don't change, check `docker compose logs api` for a config warning. The fallback is the `ghcr.io/danny-avila/librechat-dev` image, or leave the default colours and say so on the website.
- **Config errors:** after any change to `librechat.yaml`, run `docker compose restart api` and read `docker compose logs api`.

## Useful commands (run inside `vendor/LibreChat`)
```bash
docker compose ps
```
```bash
docker compose logs -f api
```
```bash
docker compose up -d --build brew-gateway
```
```bash
docker compose down
```

## Gateway tests (no Docker or key needed)
```bash
cd gateway && npm install && npm test
```

## Day-1 AWS reminder
When you create your AWS account (start of week 2 at the latest), do these first, in this order: **root MFA → AWS Budgets alert (e.g. $10) → your own IAM user with MFA**. The brief caps you at a pass if costs run away with no budget alert set.
