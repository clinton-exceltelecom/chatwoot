require 'rails_helper'

RSpec.describe Conversations::ResolutionJob do
  subject(:job) { described_class.perform_later(account: account) }

  let!(:account) { create(:account) }
  let(:label) { create(:label, title: 'auto-resolved', account: account) }
  let!(:conversation) { create(:conversation, account: account) }

  it 'enqueues the job' do
    expect { job }.to have_enqueued_job(described_class)
      .with(account: account)
      .on_queue('low')
  end

  it 'does nothing when there is no auto resolve duration' do
    described_class.perform_now(account: account)
    expect(conversation.reload.status).to eq('open')
  end

  context 'when auto_resolve_ignore_waiting is true' do
    it 'resolves non-waiting conversations if time of inactivity is more than auto resolve duration' do
      account.update(auto_resolve_after: 14_400, auto_resolve_ignore_waiting: true) # 10 days in minutes
      conversation.update(last_activity_at: 13.days.ago, waiting_since: nil)
      described_class.perform_now(account: account)
      expect(conversation.reload.status).to eq('resolved')
    end

    it 'does not resolve waiting conversations even if time of inactivity is more than auto resolve duration' do
      account.update(auto_resolve_after: 14_400, auto_resolve_ignore_waiting: true) # 10 days in minutes
      conversation.update(last_activity_at: 13.days.ago, waiting_since: 13.days.ago)
      described_class.perform_now(account: account)
      expect(conversation.reload.status).to eq('open')
    end
  end

  context 'when auto_resolve_ignore_waiting is false' do
    it 'resolves all conversations if time of inactivity is more than auto resolve duration' do
      account.update(auto_resolve_after: 14_400, auto_resolve_ignore_waiting: false) # 10 days in minutes
      # Create one waiting conversation and one non-waiting conversation
      waiting_conversation = create(:conversation, account: account, last_activity_at: 13.days.ago, waiting_since: 13.days.ago)
      non_waiting_conversation = create(:conversation, account: account, last_activity_at: 13.days.ago, waiting_since: nil)

      described_class.perform_now(account: account)

      expect(waiting_conversation.reload.status).to eq('resolved')
      expect(non_waiting_conversation.reload.status).to eq('resolved')
    end
  end

  # When a contact is deleted, there's a brief window (~50-150ms) where contact_id becomes nil
  # but conversations still exist. If ResolutionJob runs during this window, muted? can crash
  # trying to call blocked? on nil. Fixes # (issue).
  it 'skips orphan conversations without a contact' do
    account.update(auto_resolve_after: 14_400, auto_resolve_ignore_waiting: false) # 10 days in minutes
    orphan_conversation = create(:conversation, account: account, last_activity_at: 13.days.ago, waiting_since: nil)
    orphan_conversation.update_columns(contact_id: nil, contact_inbox_id: nil) # rubocop:disable Rails/SkipsModelValidations
    resolvable_conversation = create(:conversation, account: account, last_activity_at: 13.days.ago, waiting_since: nil)

    described_class.perform_now(account: account)

    expect(orphan_conversation.reload.status).to eq('open')
    expect(resolvable_conversation.reload.status).to eq('resolved')
  end

  it 'adds a label after resolution' do
    account.update(auto_resolve_label: 'auto-resolved', auto_resolve_after: 14_400)
    conversation = create(:conversation, account: account, last_activity_at: 13.days.ago, waiting_since: 13.days.ago)

    described_class.perform_now(account: account)

    expect(conversation.reload.status).to eq('resolved')
    expect(conversation.reload.label_list).to include('auto-resolved')
  end

  it 'resolves only a limited number of conversations in a single execution' do
    stub_const('Limits::BULK_ACTIONS_LIMIT', 2)
    account.update(auto_resolve_after: 14_400, auto_resolve_ignore_waiting: false) # 10 days in minutes
    create_list(:conversation, 3, account: account, last_activity_at: 13.days.ago)
    described_class.perform_now(account: account)
    expect(account.conversations.resolved.count).to eq(Limits::BULK_ACTIONS_LIMIT)
  end

  context 'when auto_resolve_during_business_hours is true' do
    let(:inbox) { create(:inbox, account: account, timezone: 'UTC', working_hours_enabled: true) }
    let(:contact_inbox) { create(:contact_inbox, inbox: inbox) }

    before do
      # Mon-Fri 09:00-17:00, Sat-Sun closed
      inbox.working_hours.find_by(day_of_week: 0).update!(closed_all_day: true)
      (1..5).each do |day|
        inbox.working_hours.find_by(day_of_week: day).update!(
          open_hour: 9, open_minutes: 0, close_hour: 17, close_minutes: 0, closed_all_day: false
        )
      end
      inbox.working_hours.find_by(day_of_week: 6).update!(closed_all_day: true)

      account.update!(auto_resolve_after: 480, auto_resolve_during_business_hours: true) # 8 business hours
    end

    it 'resolves a conversation that has exceeded 8 business hours of inactivity' do
      # last active Monday 09:00, now Monday 17:01 → just over 8 business hours
      last_active = Time.zone.parse('2026-06-22 09:00:00 UTC')
      conv = create(:conversation, account: account, inbox: inbox,
                                   contact_inbox: contact_inbox, last_activity_at: last_active)
      travel_to(Time.zone.parse('2026-06-22 17:01:00 UTC')) do
        described_class.perform_now(account: account)
      end
      expect(conv.reload.status).to eq('resolved')
    end

    it 'does not resolve a conversation that has not yet accumulated enough business hours' do
      # last active Friday 16:00, now Saturday 12:00 → only 1 business hour elapsed
      last_active = Time.zone.parse('2026-06-26 16:00:00 UTC')
      conv = create(:conversation, account: account, inbox: inbox,
                                   contact_inbox: contact_inbox, last_activity_at: last_active)
      travel_to(Time.zone.parse('2026-06-27 12:00:00 UTC')) do
        described_class.perform_now(account: account)
      end
      expect(conv.reload.status).to eq('open')
    end

    it 'resolves after enough business hours have passed spanning a weekend' do
      # last active Friday 09:00, resolved after Mon 17:00 (1 + 8 = 9 business hours > 8)
      last_active = Time.zone.parse('2026-06-26 16:00:00 UTC') # Friday 16:00 → 1h Friday
      conv = create(:conversation, account: account, inbox: inbox,
                                   contact_inbox: contact_inbox, last_activity_at: last_active)
      travel_to(Time.zone.parse('2026-06-29 16:00:00 UTC')) do # Monday 16:00 → +7h = 8h total
        described_class.perform_now(account: account)
      end
      expect(conv.reload.status).to eq('resolved')
    end

    it 'falls back to wall-clock for inboxes with working_hours_enabled false' do
      wall_clock_inbox = create(:inbox, account: account, working_hours_enabled: false)
      wall_clock_ci    = create(:contact_inbox, inbox: wall_clock_inbox)
      # 10 days ago, auto_resolve_after is 480 minutes — wall-clock easily exceeds it
      conv = create(:conversation, account: account, inbox: wall_clock_inbox,
                                   contact_inbox: wall_clock_ci, last_activity_at: 10.days.ago)
      described_class.perform_now(account: account)
      expect(conv.reload.status).to eq('resolved')
    end
  end
end
