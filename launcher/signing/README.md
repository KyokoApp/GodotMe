# Manifest signing keys

The launcher can refuse to install a manifest that is not signed with your
private key (`Config.REQUIRE_SIGNATURE`, or `--require-signature=1`, or
`"require_signature": true` in `user://retraveller/launcher_settings.json`).

Generate the pair once, on your own machine (never on a CI runner you do not
control, and never commit the private key):

```bash
openssl genrsa -out retraveller_manifest_private.pem 2048
openssl rsa -in retraveller_manifest_private.pem -pubout -out launcher/signing/public_key.pem
```

* commit **only** `public_key.pem` (the launcher ships it inside the APK);
* keep the private key somewhere safe and use it in
  `tools/make_release.py --sign-key=...`;
* losing the private key means you can no longer sign updates for the copies of
  the launcher already installed - players would need a new APK.

CI generates a throwaway pair for its own tests and never stores it.
