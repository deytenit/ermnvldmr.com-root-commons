# HAPP Subscription Generator

This tool generates `.psub` subscription files from a JSON configuration. It supports global routing via `happ://` links and multiple VLESS connection strings.

## Features
- **Global Routing**: Encodes your `routing` object into the `happ://routing/onadd/` link.
- **Templates**: Define common Xray-core settings once and reuse them across users.
- **Deep Merge**: User-specific `xray` overrides are merged with templates.
- **Auto Remarks**: Generates readable titles like `🇱🇻 Latvia [xhttp] | daedalus | clown`.
- **ISO Lookup**: Automatically converts country codes (e.g., `LV`) to names and emojis.

## Usage

The tool is designed to be run via the operator script:

```bash
./.operator/scripts/ops/generate-happ-subscriptions <input_json> <output_dir>
```

### JSON Format Spec
See `docs/plans/2026-03-17-subscription-generator-spec.md` for the full specification.

## Implementation Details
- **Logic**: Written in Python 3.11 (standard library only).
- **Isolation**: Runs inside a Docker container (`python:3.11-alpine`).
