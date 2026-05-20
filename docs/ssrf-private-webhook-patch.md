# SSRF Filter Patch — Allow Private Webhooks

## Problem

Chatwoot v4 uses the `ssrf_filter` Ruby gem (v1.5.0) which blocks outbound HTTP requests to private/reserved IP ranges. This prevents webhook delivery to cluster-internal services like `chatwoot-bot.chatwoot-bot.svc:5000` because the hostname resolves to a pod IP in `10.42.0.0/16`.

**Symptom**: Chatwoot worker logs show:
```
Exception: Invalid webhook URL http://chatwoot-bot.chatwoot-bot.svc:5000/webhook : Hostname 'chatwoot-bot.chatwoot-bot.svc' has no public ip addresses
```

Conversations are auto-opened with the activity message: *"Conversation was marked open by system due to an error with the agent bot."*

## Fix

A Ruby initializer mounted via ConfigMap monkey-patches `SsrfFilter` to allow the `10.0.0.0/8` range.

### ConfigMap: `chatwoot-ssrf-patch`

Namespace: `chatwoot`

```ruby
# Allow 10.0.0.0/8 through SsrfFilter for internal webhook delivery
class SsrfFilter
  ALLOWED_PRIVATE_RANGES = [IPAddr.new("10.0.0.0/8")].freeze

  class << self
    private

    alias_method :original_unsafe_ip_address?, :unsafe_ip_address?

    def unsafe_ip_address?(ip_address)
      return false if ip_address.ipv4? && ALLOWED_PRIVATE_RANGES.any? { |range| range.include?(ip_address) }

      original_unsafe_ip_address?(ip_address)
    end
  end
end
```

### Deployment Patches

Both `chatwoot-web` and `chatwoot-worker` deployments have:

- **Volume**: `ssrf-patch` → ConfigMap `chatwoot-ssrf-patch`
- **VolumeMount**: `/app/config/initializers/ssrf_allow_private.rb` (subPath: `ssrf_allow_private.rb`)

## Maintenance Notes

- **Helm upgrades** may overwrite the deployment volume/mount patches. Re-apply or integrate into Helm values (`extraVolumes`/`extraVolumeMounts`) before upgrading.
- The `ALLOW_PRIVATE_WEBHOOKS` env var in the `chatwoot-env` secret is inert (not a real Chatwoot config) and can be removed.
- If Chatwoot upgrades change how `SsrfFilter` is invoked or the gem is replaced, this patch will need to be revisited.

## Date

2026-05-19

## Related

- Affected service: `chatwoot-bot` (namespace `chatwoot-bot`)
- Webhook URL: `http://chatwoot-bot.chatwoot-bot.svc:5000/webhook`
- Gem source: `/gems/ruby/3.4.0/gems/ssrf_filter-1.5.0/lib/ssrf_filter/ssrf_filter.rb`
