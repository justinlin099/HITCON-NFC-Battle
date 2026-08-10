# Remote app config

The app fetches this document when it starts and when it resumes:

`https://game.hitcon2026.online/.well-known/nfc-battle-app-config.json`

```json
{
  "schema": 1,
  "api_base_url": "https://nfc-battle-staging.hitcon2026.online",
  "allow_user_tag_unlock": true,
  "show_panasonic_logo": true,
  "show_panasonic_logo_on_print": true,
  "manual_url": "https://github.com/justinlin099/HITCON-NFC-Battle#readme",
  "achievement_rules": {
    "sponsor_scout": {
      "enabled": true,
      "thresholds": [1, 5, 10]
    },
    "community_explorer": {
      "enabled": true,
      "thresholds": [1, 5, 10]
    }
  }
}
```

`show_panasonic_logo` controls Panasonic branding in app interfaces, including
expanded cards, the user's card editor, and Hero card transitions.

`show_panasonic_logo_on_print` independently controls Panasonic branding in the
print preview and the PNG uploaded for physical card printing. Both fields are
optional and default to `true`. For compatibility with older hosted configs, if
`show_panasonic_logo_on_print` is absent it inherits `show_panasonic_logo`.
The last valid values are cached separately for offline launches.

`manual_url` controls the question-mark manual button in the top-left corner of
the main interface. It may point to GitHub, GitHub Pages, or a custom domain,
but it must be a valid public HTTPS URL. The last valid URL is cached for
offline launches. When no valid remote or cached URL exists, the button stays
visible but disabled.

`achievement_rules` is the only source of achievement thresholds. Omitting the
whole object disables the achievement section. Each rule can be hidden with
`enabled: false`; every positive integer in `thresholds` creates one level. The
app compares these thresholds with `sponsor_count` and `community_count` from
`GET /missions/stamp`. A valid remote value is cached for offline launches, but
the app has no bundled achievement defaults. Configured achievement medals are
shown in a horizontally scrollable panel at the top of the scoreboard page.
