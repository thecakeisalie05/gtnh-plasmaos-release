# Packaging and publication

`tools/build_release.py` copies the runtime into `dist/release`, rejects release Lua files containing a critical placeholder marker, computes SHA-256 and byte sizes, writes the safe line-oriented `manifest.txt`, materializes the full installer and Pastebin bootstrap, and produces an offline ZIP.

Manifest paths reject absolute paths and `..`. The full installer preflights writeability, RAM, Internet/offline source, and disk capacity. It downloads each file with at most three attempts, verifies size and SHA-256, validates the boot entry, writes `.complete`, renames staging into `/system/versions/<version>`, then atomically changes the small activation pointer. `/home` is never replaced.

Publication needs external state that is intentionally absent from source control:

1. Run `python tools/build_release.py --base-url <stable-version-url>`.
2. Upload `dist/release/*` preserving paths at that URL.
3. Upload `dist/installer.lua` as `<stable-version-url>/installer.lua`.
4. Upload `dist/bootstrap.lua` to Pastebin.
5. Record the paste ID and rerun the build with `--pastebin-id <ID>` for release metadata.
6. Validate from a blank OpenOS disk using `pastebin run <ID>`.

Bootstrap validates exact installer size and, when a Data Card is present, SHA-256. Without one it warns; the full installer still validates every release file using bundled pure Lua SHA-256.
