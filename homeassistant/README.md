# Home Assistant Setup

CameraProbe notifies Home Assistant by calling two built-in webhooks - no custom component or integration needed, just two automations.

| Event | Method | URL | Body |
|---|---|---|---|
| Camera turns on | `POST` | `/api/webhook/camera_on` | `application=<AppName>` (form-encoded) |
| Camera turns off | `POST` | `/api/webhook/camera_off` | *(empty)* |

Home Assistant parses form-encoded webhook bodies automatically, so the app name is available in automation templates as `trigger.data.application`.

## Option A: Home Assistant UI

1. **Settings → Automations & Scenes → Create Automation → Create new automation**.
2. **Add Trigger → Webhook**.
3. Set **Webhook ID** to `camera_on`. Leave "Allow this trigger to be used from an external source" **off** - CameraProbe only ever calls it from your LAN.
4. **Add Action** - whatever you want to happen: turn on a light/switch, send a mobile notification, etc. To include which app triggered it in a notification message, use a template like:
   ```
   Camera turned on ({{ trigger.data.application }})
   ```
5. Save, name it something like "CameraProbe - Camera On".
6. Repeat steps 1-5 for a second automation with **Webhook ID** `camera_off`, with whichever "turn off" action mirrors the first.

## Option B: YAML

If you manage automations as YAML, copy [`automations.example.yaml`](automations.example.yaml) into your `automations.yaml` (or merge the two automation entries into your existing list), then edit the `entity_id` / `notify.notify` target to match your setup. Reload automations afterward: **Developer Tools → YAML → Automations**, or restart Home Assistant.

## Testing without touching the camera

```
curl -X POST http://homeassistant.local:8123/api/webhook/camera_on -d "application=TestApp"
curl -X POST http://homeassistant.local:8123/api/webhook/camera_off
```

Check **Settings → Automations & Scenes**, open the automation, and look at its trace history (⋮ menu → Traces) to confirm it fired and see what `trigger.data` looked like.

## Notes

- `local_only: true` on the trigger is a deliberate safety choice - these webhooks aren't authenticated, so they shouldn't be reachable from outside your network. Don't expose your Home Assistant instance's webhook endpoints to the internet without additional protection.
- CameraProbe's `--test` and `--status` commands only check that Home Assistant is *reachable* on the configured host/port - they don't verify the automations themselves are set up correctly. Use the `curl` commands above for that.
- Disable the Home Assistant integration entirely by setting `"homeAssistant": { "enabled": false }` in `config.json` if you don't want it.
