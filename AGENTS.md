# PindouAI Project Rules

- Purpose: Flutter bead-pattern studio that converts photos and text into buildable bead charts, supports manual boards, local project management, palette lookup, export, and optional AI services.
- Stack: Flutter/Dart client; optional FastAPI backend in `backend/`; optional Vue/FastAPI AI workspace in `ai-platform/`.
- Main entry points: `lib/main.dart`, `backend/app/main.py`, and `ai-platform/frontend/src/main.ts`.
- Important directories: `lib/` application code, `test/` Flutter tests, `assets/` runtime assets, `docs/` product docs and GitHub Pages, `backend/` optional API, `ai-platform/` optional AI workspace.
- Setup: `flutter pub get`.
- Required checks for source changes: `flutter analyze` and risk-appropriate `flutter test` targets. Run the full suite before a release or broad shared change.
- Web showcase checks: serve `docs/` locally and verify desktop/mobile layout, links, images, keyboard access, and console errors in a real browser.
- Never commit `.env`, API keys, signing keys, local databases, `.venv`, build caches, root APK/EXE/ZIP files, the external source-material directory, or its Android junction at `android/app/src/main/assets/pindou_originals/`.
- The repository tracks only original `sample_*.png` images and `manifest.opensource.json` under `assets/pindou_collection/`. The larger local collection is ignored and must never be published without verified redistribution rights.
- Keep product behavior in `docs/PRD.md`, architecture in `docs/ARCHITECTURE.md`, usage in `README.md`, and durable workflow rules here.
- Use `main` as the public default branch. Commit, push, tag, release, and publish only after local checks pass. Never rewrite or delete published history unless the user explicitly requests it.
- Preserve user files and untracked local material. Do not clean caches or large assets merely to make Git status shorter.
