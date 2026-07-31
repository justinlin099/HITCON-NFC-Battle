# hitcon_nfc_battle

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## Generate staging test tokens

`tool/generate_test_tokens.ps1` creates locally verified HS256 JWTs without
storing the signing secret in the repository. Run it from PowerShell:

```powershell
.\tool\generate_test_tokens.ps1 -UserId test_attendee_017
```

To generate a numbered batch:

```powershell
.\tool\generate_test_tokens.ps1 `
  -Prefix test_attendee_ `
  -Start 17 `
  -Count 10
```

The script reads `JWT_SECRET` from the environment. If it is missing, the script
prompts for it without echoing the value. It defaults to the staging issuer and
audience; use `-Issuer` and `-Audience` to override them. `-AsJson` produces JSON,
and `-OutputPath` writes the untruncated output to a file. Root-level files named
`test-tokens*.json` or `test-tokens*.txt` are ignored by Git.

`-VerifyWithApi` additionally calls staging `GET /users/me`. This creates a
default staging profile when the token subject does not already exist.
