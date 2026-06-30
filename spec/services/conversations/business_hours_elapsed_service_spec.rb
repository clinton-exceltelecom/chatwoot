require 'rails_helper'

RSpec.describe Conversations::BusinessHoursElapsedService do
  subject(:service) { described_class.new(conversation) }

  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account, timezone: 'UTC') }
  let(:contact_inbox) { create(:contact_inbox, inbox: inbox) }
  let(:conversation) do
    create(:conversation, account: account, inbox: inbox, contact_inbox: contact_inbox)
  end

  # Helper: set working hours for the inbox to Mon-Fri 09:00-17:00, Sat-Sun closed
  def setup_working_hours
    inbox.update!(working_hours_enabled: true)
    inbox.working_hours.find_by(day_of_week: 0).update!(closed_all_day: true)  # Sun
    (1..5).each do |day|
      inbox.working_hours.find_by(day_of_week: day).update!(
        open_hour: 9, open_minutes: 0,
        close_hour: 17, close_minutes: 0,
        closed_all_day: false
      )
    end
    inbox.working_hours.find_by(day_of_week: 6).update!(closed_all_day: true)  # Sat
  end

  context 'when working_hours_enabled is false' do
    it 'returns wall-clock elapsed minutes' do
      conversation.update!(last_activity_at: 60.minutes.ago)
      expect(service.elapsed_minutes).to be_within(1).of(60)
    end
  end

  context 'when working_hours_enabled is true' do
    before { setup_working_hours }

    it 'returns 0 when last_activity_at is in the future' do
      conversation.update!(last_activity_at: 5.minutes.from_now)
      expect(service.elapsed_minutes).to eq(0)
    end

    it 'counts minutes within the same open business day' do
      # Wednesday 10:00 UTC → Wednesday 12:00 UTC = 2 open hours
      last_active = Time.zone.parse('2026-06-24 10:00:00 UTC') # Wednesday
      now         = Time.zone.parse('2026-06-24 12:00:00 UTC')

      conversation.update!(last_activity_at: last_active)
      travel_to(now) do
        expect(service.elapsed_minutes).to be_within(1).of(120)
      end
    end

    it 'does not count time outside open hours on the same day' do
      # Wednesday 16:00 → Wednesday 18:00 — only 1h is inside the 09-17 window
      last_active = Time.zone.parse('2026-06-24 16:00:00 UTC')
      now         = Time.zone.parse('2026-06-24 18:00:00 UTC')

      conversation.update!(last_activity_at: last_active)
      travel_to(now) do
        expect(service.elapsed_minutes).to be_within(1).of(60)
      end
    end

    it 'does not count time on a closed day (Saturday)' do
      # Friday 16:00 → Saturday 12:00 — only 1h of Friday open time counts
      last_active = Time.zone.parse('2026-06-26 16:00:00 UTC') # Friday
      now         = Time.zone.parse('2026-06-27 12:00:00 UTC') # Saturday

      conversation.update!(last_activity_at: last_active)
      travel_to(now) do
        expect(service.elapsed_minutes).to be_within(1).of(60)
      end
    end

    it 'spans multiple business days correctly' do
      # Monday 09:00 → Wednesday 17:00 = 3 full days × 8h = 24h = 1440 minutes
      last_active = Time.zone.parse('2026-06-22 09:00:00 UTC') # Monday
      now         = Time.zone.parse('2026-06-24 17:00:00 UTC') # Wednesday

      conversation.update!(last_activity_at: last_active)
      travel_to(now) do
        expect(service.elapsed_minutes).to be_within(1).of(1440)
      end
    end

    it 'skips the weekend when spanning Friday to Monday' do
      # Friday 16:00 → Monday 10:00 = 1h Friday + 1h Monday = 120 minutes
      last_active = Time.zone.parse('2026-06-26 16:00:00 UTC') # Friday
      now         = Time.zone.parse('2026-06-29 10:00:00 UTC') # Monday

      conversation.update!(last_activity_at: last_active)
      travel_to(now) do
        expect(service.elapsed_minutes).to be_within(1).of(120)
      end
    end

    it 'returns 0 when last_activity_at is after close time on the same day' do
      # Wednesday 18:00 (after close) → Wednesday 19:00 — no open time in window
      last_active = Time.zone.parse('2026-06-24 18:00:00 UTC')
      now         = Time.zone.parse('2026-06-24 19:00:00 UTC')

      conversation.update!(last_activity_at: last_active)
      travel_to(now) do
        expect(service.elapsed_minutes).to eq(0)
      end
    end

    context 'with open_all_day set' do
      it 'counts the full day when open_all_day is true' do
        inbox.working_hours.find_by(day_of_week: 6).update!(
          closed_all_day: false, open_all_day: true,
          open_hour: 0, open_minutes: 0, close_hour: 23, close_minutes: 59
        )
        # Saturday 08:00 → Saturday 20:00 = 12h = 720 minutes
        last_active = Time.zone.parse('2026-06-27 08:00:00 UTC') # Saturday
        now         = Time.zone.parse('2026-06-27 20:00:00 UTC')

        conversation.update!(last_activity_at: last_active)
        travel_to(now) do
          expect(service.elapsed_minutes).to be_within(1).of(720)
        end
      end
    end
  end
end
