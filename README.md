# pretense.ai — public marketing site (static export)

Built output only, served by GitHub Pages so the site is up 24/7 with no server.
There is no source code, configuration or engine code in this repository. Every
push goes through a privacy guard that blocks secrets, source files, source maps,
binaries and internal hostnames.

- The marketing pages, docs, case studies, `install.sh` and `llms.txt` are served from here.
- App routes (`/login`, `/signup`, `/dashboard`, …) forward to the app origin.
- The CLI binaries are not stored here.
