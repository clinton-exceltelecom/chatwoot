# Inline CSAT Email Rating

## Summary

Replace the current "Click here to rate" link in CSAT email notifications with clickable rating icons (emojis or stars) that link to the existing survey page with a `#rating-N` fragment. The Vue survey page detects the fragment and auto-submits the rating on load.

## Problem

The current CSAT email experience sends a plain text link that takes the user to a separate page before they can rate. This adds friction — the user must click, wait for the page to load, then click again to rate. Many users never complete the survey.

## Solution

Embed the 5 rating options directly in the email as clickable links. Each link points to the existing survey page with a URL fragment (`#rating-1` through `#rating-5`). The Vue app reads the fragment on mount and auto-submits the rating, then shows the feedback form.

### Why Fragments

- **No link prefetch risk** — fragments are never sent to the server, so email security scanners (SafeLinks, Mimecast, Barracuda) cannot accidentally trigger a rating
- **No new backend endpoint** — everything is handled client-side
- **Graceful degradation** — if JS fails, the user is still on the survey page and can rate manually

## Design

### Email Template

The email renders 5 clickable rating icons based on the inbox's `display_type` setting, plus a plain-text fallback link:

- **emoji** (default): 😞 😑 😐 😀 😍
- **star**: ⭐ ⭐ ⭐ ⭐ ⭐

Each icon links to:

```
{FRONTEND_URL}/survey/responses/{conversation_uuid}#rating-{1-5}
```

A fallback link below handles cases where emojis are stripped or HTML is blocked:

```
Rate this conversation → {FRONTEND_URL}/survey/responses/{conversation_uuid}
```

### Frontend (Vue)

The `Response.vue` component reads `window.location.hash` on mount. If it matches `#rating-N` and no rating has been submitted yet, it auto-calls `selectRating(N)` which submits the rating via the existing API.

### Existing Survey Page Behavior After Auto-Submit

1. Rating is submitted via PATCH
2. Success banner appears
3. Feedback textarea is revealed
4. User can optionally type feedback and submit

## Files to Change

### Frontend

| File | Change |
|------|--------|
| `app/javascript/survey/views/Response.vue` | Read `window.location.hash` on mount, auto-submit rating if fragment matches `#rating-N` |

### Email Templates

| File | Change |
|------|--------|
| `app/views/mailers/conversation_reply_mailer/reply_with_summary.html.erb` | Replace "Click here" link with inline rating icons + fallback link |
| `app/views/mailers/conversation_reply_mailer/reply_without_summary.html.erb` | Add CSAT rendering for `input_csat` messages |
| `app/views/mailers/conversation_reply_mailer/email_reply.html.erb` | Replace plain survey URL with inline rating icons + fallback link |

### Shared Partial (new)

| File | Purpose |
|------|---------|
| `app/views/mailers/conversation_reply_mailer/_csat_rating.html.erb` | Shared partial for rendering rating icons + fallback, accepts `message` as local |

### Tests

| File | Change |
|------|--------|
| `spec/mailers/conversation_reply_mailer_spec.rb` | Verify inline rating icons render correctly for both display types, verify fallback link present |
| `spec/javascript/survey/views/Response.spec.js` (or equivalent) | Verify fragment detection triggers `selectRating` |

## Implementation Steps

### Step 1: Create the email partial

```erb
<%# app/views/mailers/conversation_reply_mailer/_csat_rating.html.erb %>
<% survey_url = "#{ENV.fetch('FRONTEND_URL', '')}/survey/responses/#{message.conversation.uuid}" %>
<% display_type = message.content_attributes&.dig('display_type') || 'emoji' %>
<p><%= message.content %></p>
<p style="font-size: 28px; line-height: 1.8;">
  <% if display_type == 'star' %>
    <% (1..5).each do |value| %>
      <a href="<%= survey_url %>#rating-<%= value %>" style="text-decoration:none;" target="_blank">⭐</a>
    <% end %>
  <% else %>
    <% [[1,'😞'],[2,'😑'],[3,'😐'],[4,'😀'],[5,'😍']].each do |value, emoji| %>
      <a href="<%= survey_url %>#rating-<%= value %>" style="text-decoration:none;" target="_blank"><%= emoji %></a>
    <% end %>
  <% end %>
</p>
<p style="font-size: 12px; color: #666;">
  <a href="<%= survey_url %>" target="_blank">Rate this conversation</a>
</p>
```

### Step 2: Update email templates

Replace the existing CSAT rendering in each template with:

```erb
<% if message.content_type == 'input_csat' && message.message_type == 'template' %>
  <%= render partial: 'mailers/conversation_reply_mailer/csat_rating', locals: { message: message } %>
<% else %>
  <%# existing message rendering %>
<% end %>
```

For `email_reply.html.erb`, add a check for `@message.input_csat?` before the existing content rendering.

### Step 3: Update Response.vue

```javascript
async mounted() {
  await this.getSurveyDetails();
  const match = window.location.hash.match(/^#rating-(\d)$/);
  if (match && !this.isRatingSubmitted) {
    this.selectRating(parseInt(match[1], 10));
  }
}
```

### Step 4: Write tests

**Mailer specs:**
- Emoji display type renders 5 emoji links with correct `#rating-N` fragments
- Star display type renders 5 star links with correct fragments
- Fallback plain link is always present
- Links contain the correct conversation UUID

**Frontend specs:**
- `#rating-3` in URL triggers `selectRating(3)` after survey loads
- No fragment does not auto-submit
- Already-submitted rating is not overwritten by fragment
- Invalid fragment (e.g., `#rating-9`) is ignored

## Edge Cases

| Case | Handling |
|------|----------|
| Rating already submitted | Fragment is ignored (`!this.isRatingSubmitted` check) |
| Survey expired (>14 days) | Page loads normally, API returns 422 on submit attempt, error banner shown |
| Invalid fragment value | Regex only matches single digit 1-5, anything else is ignored |
| JS disabled | User sees the survey page, can rate manually |
| HTML stripped by email client | Fallback plain link still works |
| Link prefetch by security scanner | Fragment not sent to server, page loads but no JS executes in scanner context |

## Rollout

1. Implement and test on `feature/inline-csat-email-rating` branch
2. Build and push image to Harbor
3. Deploy to staging/dev for manual testing
4. Verify with multiple email clients (Gmail, Outlook, Apple Mail, mobile)
5. Deploy to production
