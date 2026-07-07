require 'rails_helper'

RSpec.describe Automations::TimerTriggerJob do
  subject(:job) { described_class.perform_later }

  let!(:account) { create(:account) }

  # Minimal timer rule factory helper
  def create_timer_rule(account:, anchor:, duration_minutes:, conditions: nil, actions: nil)
    conditions ||= [{ 'attribute_key' => 'status', 'filter_operator' => 'equal_to',
                      'values' => ['open'], 'query_operator' => nil }]
    actions ||= [{ 'action_name' => 'assign_team', 'action_params' => [] }]
    AutomationRule.create!(
      account: account,
      name: "Timer rule - #{anchor}",
      event_name: 'time_elapsed',
      schedule_anchor: anchor,
      schedule_duration_minutes: duration_minutes,
      conditions: conditions,
      actions: actions,
      active: true
    )
  end

  it 'enqueues the job' do
    expect { job }.to have_enqueued_job(described_class).on_queue('scheduled_jobs')
  end

  describe '#perform' do
    context 'when no timer rules exist' do
      it 'does nothing' do
        expect(AutomationRules::ActionService).not_to receive(:new)
        described_class.perform_now
      end
    end

    context 'with a rule anchored to conversation_created' do
      let!(:rule) { create_timer_rule(account: account, anchor: 'conversation_created', duration_minutes: 60) }

      it 'runs actions on conversations older than the threshold' do
        old_conversation = create(:conversation, account: account, created_at: 2.hours.ago)
        fresh_conversation = create(:conversation, account: account, created_at: 30.minutes.ago)

        action_service = instance_double(AutomationRules::ActionService, perform: true)
        condition_service_old = instance_double(AutomationRules::ConditionsFilterService, perform: [true])
        condition_service_fresh = instance_double(AutomationRules::ConditionsFilterService, perform: [])

        allow(AutomationRules::ConditionsFilterService).to receive(:new)
          .with(rule, old_conversation, {}).and_return(condition_service_old)
        allow(AutomationRules::ConditionsFilterService).to receive(:new)
          .with(rule, fresh_conversation, {}).and_return(condition_service_fresh)
        allow(AutomationRules::ActionService).to receive(:new)
          .with(rule, account, old_conversation).and_return(action_service)

        described_class.perform_now

        expect(AutomationRules::ActionService).to have_received(:new).with(rule, account, old_conversation).once
        expect(AutomationRules::ActionService).not_to have_received(:new).with(rule, account, fresh_conversation)
      end
    end

    context 'with a rule anchored to waiting_since' do
      let!(:rule) { create_timer_rule(account: account, anchor: 'waiting_since', duration_minutes: 1440) }

      it 'runs actions on conversations waiting longer than the threshold' do
        # Use update_columns to bypass the ensure_waiting_since before_create callback
        waiting_long = create(:conversation, account: account)
        waiting_long.update_columns(waiting_since: 2.days.ago) # rubocop:disable Rails/SkipsModelValidations

        _waiting_short = create(:conversation, account: account)
        _waiting_short.update_columns(waiting_since: 12.hours.ago) # rubocop:disable Rails/SkipsModelValidations

        _not_waiting = create(:conversation, account: account)
        _not_waiting.update_columns(waiting_since: nil) # rubocop:disable Rails/SkipsModelValidations

        action_service = instance_double(AutomationRules::ActionService, perform: true)
        allow(AutomationRules::ConditionsFilterService).to receive(:new)
          .and_return(instance_double(AutomationRules::ConditionsFilterService, perform: [true]))
        allow(AutomationRules::ActionService).to receive(:new).and_return(action_service)

        described_class.perform_now

        # Only waiting_long meets the 1440-minute threshold (2 days > 1 day)
        expect(AutomationRules::ActionService).to have_received(:new)
          .with(rule, account, waiting_long).once
        expect(AutomationRules::ActionService).to have_received(:new).exactly(1).times
      end

      it 'skips conversations where waiting_since is nil' do
        conv = create(:conversation, account: account)
        conv.update_columns(waiting_since: nil) # rubocop:disable Rails/SkipsModelValidations

        expect(AutomationRules::ActionService).not_to receive(:new)
        described_class.perform_now
      end
    end

    context 'when conditions do not match' do
      let!(:rule) { create_timer_rule(account: account, anchor: 'last_activity', duration_minutes: 30) }

      it 'does not run actions' do
        create(:conversation, account: account, last_activity_at: 2.hours.ago)

        allow(AutomationRules::ConditionsFilterService).to receive(:new)
          .and_return(instance_double(AutomationRules::ConditionsFilterService, perform: []))

        expect(AutomationRules::ActionService).not_to receive(:new)
        described_class.perform_now
      end
    end

    context 'with orphan conversations (contact deleted)' do
      let!(:rule) { create_timer_rule(account: account, anchor: 'conversation_created', duration_minutes: 60) }

      it 'skips orphan conversations' do
        orphan = create(:conversation, account: account, created_at: 2.hours.ago)
        orphan.update_columns(contact_id: nil, contact_inbox_id: nil) # rubocop:disable Rails/SkipsModelValidations

        expect(AutomationRules::ActionService).not_to receive(:new)
        described_class.perform_now
      end
    end

    context 'with an inactive timer rule' do
      it 'does not process inactive rules' do
        create_timer_rule(account: account, anchor: 'conversation_created', duration_minutes: 60).update!(active: false)
        create(:conversation, account: account, created_at: 2.hours.ago)

        expect(AutomationRules::ActionService).not_to receive(:new)
        described_class.perform_now
      end
    end

    context 'when action service raises an error' do
      let!(:rule) { create_timer_rule(account: account, anchor: 'conversation_created', duration_minutes: 60) }

      it 'captures the exception and continues processing other conversations' do
        conversation1 = create(:conversation, account: account, created_at: 2.hours.ago)
        conversation2 = create(:conversation, account: account, created_at: 2.hours.ago)

        exception_tracker = instance_double(ChatwootExceptionTracker, capture_exception: true)
        allow(ChatwootExceptionTracker).to receive(:new).and_return(exception_tracker)
        allow(AutomationRules::ConditionsFilterService).to receive(:new)
          .and_return(instance_double(AutomationRules::ConditionsFilterService, perform: [true]))

        call_count = 0
        allow(AutomationRules::ActionService).to receive(:new).and_wrap_original do |_original, *_args|
          call_count += 1
          raise StandardError, 'something went wrong' if call_count == 1

          instance_double(AutomationRules::ActionService, perform: true)
        end

        expect { described_class.perform_now }.not_to raise_error
        expect(AutomationRules::ActionService).to have_received(:new).twice
      end
    end
  end
end
