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
- **Status**: ✅ Confirmed serving real MongoDB data (not sample fallback).

### 2. Data Collector (The Robot/Scraper)
- **Technology**: Python + Playwright (Chromium)
- **Execution**: GitHub Actions, **self-hosted runner on this PC** (not GitHub-hosted — see below)
- **Schedule**: Every **2 days at 12:00 UTC**, plus manual trigger anytime (`workflow_dispatch`)
- **Storage**: Performs `upsert` operations on the `events` collection in MongoDB Atlas.
- **Lookahead window**: current month + 3 following months (~90 days), matching the app's 45-day forward calendar with margin.
- **Configuration**: `.github/workflows/scrape.yml`
- **Key Environment Variable**: `MONGODB_URI` (Stored in GitHub Actions Secrets)
- **⚠️ Important — why self-hosted**: zaragoza.es blocks network traffic from GitHub-hosted runner IPs (Azure datacenter ranges) at the TCP level — confirmed with a plain `curl` that times out before any HTTP request completes, so it's not fixable in code. The workflow runs on a self-hosted runner installed on this machine instead (normal residential connection, not blocked).
- **Runner setup status**: workflow is configured for `runs-on: self-hosted`, but the runner software itself has **not been installed yet** on this PC (pending — see Pending Tasks). Until it's installed, scheduled/manual runs will show as queued/unavailable in GitHub Actions.
- **If the PC is off** at the scheduled time: that run is simply skipped, no error, no data loss — MongoDB just keeps serving the last successfully scraped data until the next run succeeds. Not critical since events are scraped ~90 days ahead of time.

### 3. Database (Cloud Store)
- **Provider**: MongoDB Atlas (Free Tier)
- **Database Name**: `zaragoza_cultura`
- **Collection**: `events`
- **User**: `robot_cultura` (with readWrite permissions)

### 4. Frontend (Mobile App)
- **Technology**: Flutter
- **Target**: Android (Xiaomi)
- **Current Status**: APK builds successfully (locally, on this PC) and includes all fixes below. Installed/tested on Xiaomi — pending confirmation that real events show up now that the scraper's month limitation is fixed.
- **Flutter SDK Path**: `C:\flutter` (Moved from Users folder to avoid encoding issues with tildes/accents).
- **Build note**: building the APK must be done from a normal local terminal, not through a remote/sandboxed agent session — a JDK-level Windows socket issue (`Unable to establish loopback connection`, unrelated to this project) only reproduces in that kind of nested-process execution environment.
- **Build command**:
  ```powershell
  $env:GRADLE_USER_HOME = "C:\gradle_home"
  cd C:\ZaragozaCulturaApp
  flutter build apk --release
  ```
  (or double-click `generar_apk.bat` in the project root, which does the same thing.)

## 🛠️ Recent Changes & Fixes (chronological)
- **Decoupling**: Removed `subprocess.run` from `server.py` to avoid timeouts and memory crashes on Render.
- **Persistence**: Replaced `zaragoza_events.json` with MongoDB Atlas for persistent cloud storage.
- **OS Fix**: Moved Flutter SDK to `C:\flutter` to solve Gradle build errors caused by the tilde in the user folder (`Jesús`).
- **2026-09-28 — Root cause of "app finds no activities" (three separate bugs)**:
  1. `lib/main.dart` only listed `10.0.2.2`/`localhost`/`127.0.0.1` as API URLs — none reachable from a real phone. **Fixed**: added `https://zaragoza-cultura-app.onrender.com/events` as the primary URL.
  2. The MongoDB migration commit had never been pushed to GitHub — Render was deploying the old pre-MongoDB `server.py`. **Fixed**: merged local and remote git history and pushed.
  3. The scraper's daily cron trigger had been silently disabled (`workflow_dispatch` only). **Fixed**, then later changed to weekly (see below).
- **2026-09-28 — AndroidManifest.xml missing `INTERNET` permission**: the app could never reach any network endpoint at all, regardless of URL — always fell back to bundled sample data. **Fixed**: added `<uses-permission android:name="android.permission.INTERNET"/>`.
- **2026-09-28 — 10s network timeout too short**: Render's free tier sleeps after ~15 min idle and can take 30-60s to wake up; a 10s client timeout meant the app looked broken whenever Render had gone to sleep. **Fixed**: raised to 45s, and added pull-to-refresh so a failed first load can be retried without restarting the app.
- **2026-09-28 — Scraper only ever looked at the current calendar month**: both the public-calendar cross-check (Playwright) and the dataset API date-range query were bounded to "this month", so events already published for next month (e.g. multi-week Fiestas del Pilar activities) never reached the app even though its own calendar looks 45 days ahead. **Fixed**: both now cover the current + 3 following months (~90 days).
- **2026-09-28 — Per-occurrence `endDate` bug**: every generated daily occurrence carried the whole sub-event's end date instead of its own day, showing a misleading date range on the event detail screen. **Fixed**.
- **2026-09-28 — zaragoza.es blocks GitHub-hosted runner IPs**: discovered when the scraper started failing with `ERR_CONNECTION_TIMED_OUT` / plain `curl` timeouts from GitHub Actions. **Fixed** (workflow-side) by switching to `runs-on: self-hosted` and moving the schedule to Monday 12:00 UTC (was daily 03:00, but the runner machine isn't on that early and freshness isn't critical for events planned weeks ahead).

## ✅ Already working (verified, no action needed)
- **Images from the official site**: `scraper.py` already extracts `imageUrl` from the official dataset's `image` field. Confirmed live: 2930/2930 events had a populated image.
- **Day/time schedules ("Lugares de realización")**: already correctly parsed from the dataset API's `subEvent[].openingHours[]` (dayOfWeek + startTime), which is the exact same structured data behind the website's "Lugares de realización" table — verified by comparing the two side by side for a real event.

## 📅 Pending Tasks
- [ ] **Install the self-hosted GitHub Actions runner on this PC** (`C:\actions-runner`) and register it against `zgzcult/ZaragozaCulturaApp`, ideally installed as a Windows service (`svc.cmd install` / `svc.cmd start`) so it survives reboots. Registration token comes from `https://github.com/zgzcult/ZaragozaCulturaApp/settings/actions/runners/new` (short-lived, must be fetched right before running `config.cmd`).
- [ ] Trigger a manual scraper run once the runner is installed and confirm it completes successfully and populates events across the wider ~90-day window.
- [ ] Reinstall the latest APK on the Xiaomi and confirm real events (with images and schedules) show up across multiple days, not just today.

## 🔑 Credentials Management
- All sensitive data (`MONGODB_URI`) is stored as **Secrets** in Render and GitHub.
- **NEVER** hardcode these in the source files.
- A GitHub Personal Access Token was pasted in plaintext in chat on 2026-09-28 to work around a push permission issue — **it should be revoked/rotated** if that hasn't been done already, and a GitHub collaborator invite (`jhuspi2` on `zgzcult/ZaragozaCulturaApp`) was used instead going forward.
