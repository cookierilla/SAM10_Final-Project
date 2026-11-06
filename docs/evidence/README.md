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

## Still to capture (needs AWS)
E-02 deployed URL · E-06 dashboard · E-07 alarms · E-08 alert email · E-10 backup settings · E-11 restore · E-12 MFA + IAM users · E-13 Parameter Store · E-14 automations · E-16 cost · E-17 Well-Architected review · E-18 infrastructure diagram.

## How the screenshots were taken
E-01 and E-03 screenshots were captured with a headless Microsoft Edge browser driven by a Playwright script (Claude-assisted), logged in as an invented demo account. The answers shown are real, unedited model output. E-05 screenshots were taken by hand.
