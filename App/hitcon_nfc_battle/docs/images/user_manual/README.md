# User manual images

`published/` contains the resized PNG files referenced by both user manuals. Keeping every published image below the Markdown files' `docs/` directory avoids local preview sandboxes blocking `../` paths, and standard Markdown image syntax works in GitHub, VS Code, and stricter local viewers.

Source files remain unchanged:

- App icon: `assets/app_icon/app_icon_master.png`
- Quick Start comics: `artifacts/nfc_badge_onboarding_comic/app-ui-v1/`
- Printing comics: `artifacts/card_purchase_comic/app-ui-v3/`
- Achievement badges: `assets/images/achievement_badges/`
- App screenshots: the full-size PNG files in this directory

Published widths are 180 px for the icon, 620 px for Quick Start comics, 560 px for printing comics, 360 px for App screenshots, and 120 px for achievement badges. `app-icon-rounded.png` preserves the published icon artwork and applies a 32 px transparent corner radius for the manual header. Regenerate the derivatives whenever a source image changes.
