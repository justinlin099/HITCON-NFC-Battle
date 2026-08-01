# Remote app config

The app fetches this document when it starts and when it resumes:

`https://game.hitcon2026.online/.well-known/nfc-battle-app-config.json`

```json
{
  "schema": 1,
  "api_base_url": "https://nfc-battle-staging.hitcon2026.online",
  "allow_user_tag_unlock": true,
  "show_panasonic_logo": true,
  "show_panasonic_logo_on_print": true
}
```

`show_panasonic_logo` controls Panasonic branding in app interfaces, including
expanded cards, the user's card editor, and Hero card transitions.

`show_panasonic_logo_on_print` independently controls Panasonic branding in the
print preview and the PNG uploaded for physical card printing. Both fields are
optional and default to `true`. For compatibility with older hosted configs, if
`show_panasonic_logo_on_print` is absent it inherits `show_panasonic_logo`.
The last valid values are cached separately for offline launches.
