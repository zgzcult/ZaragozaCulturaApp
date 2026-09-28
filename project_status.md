# Project Status: Zaragoza Cultura App
Date: 2026-09-28 (updated)

## 🌟 Architecture Overview
The app has been migrated from a local-file system to a professional decoupled cloud architecture to solve Render's free tier limitations.

### 1. Backend (API Server)
- **Technology**: Python (http.server)
- **Hosting**: Render (Web Service)
- **Storage**: MongoDB Atlas (Cloud)
- **Key Environment Variable**: `MONGODB_URI` (Stored in Render Secrets)
- **Function**: Lightweight API that fetches events from MongoDB and serves them as JSON to the Flutter app.

### 2. Data Collector (The Robot/Scraper)
- **Technology**: Python + Playwright (Chromium)
- **Execution**: GitHub Actions (Cron Job)
- **Schedule**: Every day at 03:00 UTC
- **Storage**: Performs `upsert` operations on the `events` collection in MongoDB Atlas.
- **Configuration**: `.github/workflows/scrape.yml`
- **Key Environment Variable**: `MONGODB_URI` (Stored in GitHub Actions Secrets)

### 3. Database (Cloud Store)
- **Provider**: MongoDB Atlas (Free Tier)
- **Database Name**: `zaragoza_cultura`
- **Collection**: `events`
- **User**: `robot_cultura` (with readWrite permissions)

### 4. Frontend (Mobile App)
- **Technology**: Flutter
- **Target**: Android (Xiaomi)
- **Current Status**: Pending final APK installation.
- **Flutter SDK Path**: `C:\flutter` (Moved from Users folder to avoid encoding issues with tildes/accents).

## 🛠️ Recent Changes & Fixes
- **Decoupling**: Removed `subprocess.run` from `server.py` to avoid timeouts and memory crashes on Render.
- **Persistence**: Replaced `zaragoza_events.json` with MongoDB Atlas for persistent cloud storage.
- **Automation**: Implemented GitHub Actions for daily automatic scraping.
- **OS Fix**: Moved Flutter SDK to `C:\flutter` to solve Gradle build errors caused by the tilde in the user folder (`Jesús`).
- **Workflow Fix (2026-09-21)**: Fixed YAML syntax in `.github/workflows/scrape.yml` (indentation error). Verified that the scraper runs successfully and populates the `events` collection in MongoDB Atlas.
- **Network Config (2026-09-21)**: Verified MongoDB Atlas Network Access is set to `0.0.0.0/0` to allow Render connections.

## 🐞 Root Cause Found (2026-09-28)
Three confirmed bugs explained "la app falla en algo":

1. **Flutter app never called Render.** `lib/main.dart` only listed `10.0.2.2`/`localhost`/`127.0.0.1` as API URLs — none reachable from a real phone, so the app always fell back to bundled sample data. **Fixed**: added `https://zaragoza-cultura-app.onrender.com/events` as the primary URL.
2. **The MongoDB migration commit was never pushed to GitHub.** Local `main` and `origin/main` had diverged since commit `c249df0` — GitHub kept the old pre-MongoDB `server.py`/`scraper.py` (edited only via the GitHub web UI for `scrape.yml`), while the Mongo version only existed on this machine. Since Render deploys from `origin/main`, it was running the old server, which explains the observed `sample-001/002/003` fallback data confirmed via `curl https://zaragoza-cultura-app.onrender.com/events`. **Fixed**: merged both histories, local Mongo-based `backend/server.py` / `backend/scraper/scraper.py` are now what gets pushed and deployed.
3. **Daily scraper cron was disabled.** The active `.github/workflows/scrape.yml` only had `workflow_dispatch` (manual trigger) — no `schedule`. A correct version with the cron existed but was saved as `scrape.yml.txt` (ignored by GitHub Actions). **Fixed**: restored `schedule: cron: '0 3 * * *'` in the active `scrape.yml`; removed the stale `.txt` duplicate and the duplicate root-level `requirements.txt`/`scraper.py`/`server.py` files.

## 📅 Pending Tasks
- [ ] Verify Render redeploys from the updated `main` and `/events` now returns real MongoDB data (not `sample-00x`).
- [ ] Verify the next scheduled GitHub Actions run (03:00 UTC) executes and upserts into MongoDB.
- [ ] Final APK generation: `flutter build apk --release` with the corrected API URL.
- [ ] Installation of `app-release.apk` on Xiaomi device and confirm real events load.

## 🔑 Credentials Management
- All sensitive data (`MONGODB_URI`) is stored as **Secrets** in Render and GitHub.
- **NEVER** hardcode these in the source files.
