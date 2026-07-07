require 'rails_helper'
require Rails.root.join 'spec/models/concerns/reauthorizable_shared.rb'

RSpec.describe AutomationRule do
  describe 'concerns' do
    it_behaves_like 'reauthorizable'
  end

  describe 'associations' do
    let(:account) { create(:account) }
    let(:params) do
      {
        name: 'Notify Conversation Created and mark priority query',
        description: 'Notify all administrator about conversation created and mark priority query',
        event_name: 'conversation_created',
        account_id: account.id,
        conditions: [
          {
            attribute_key: 'browser_language',
            filter_operator: 'equal_to',
            values: ['en'],
            query_operator: 'AND'
          },
          {
            attribute_key: 'country_code',
            filter_operator: 'equal_to',
            values: %w[USA UK],
            query_operator: nil
          }
        ],
        actions: [
          {
            action_name: :send_message,
            action_params: ['Welcome to the chatwoot platform.']
          },
          {
            action_name: :assign_team,
            action_params: [1]
          },
          {
            action_name: :remove_assigned_agent
          },
          {
            action_name: :remove_assigned_team
          },
          {
            action_name: :add_label,
            action_params: %w[support priority_customer]
          },
          {
            action_name: :assign_agent,
            action_params: [1]
          }
        ]
      }.with_indifferent_access
    end

    it 'returns valid record' do
      rule = FactoryBot.build(:automation_rule, params)
      expect(rule.valid?).to be true
    end

    it 'returns invalid record' do
      params[:conditions][0].delete('query_operator')
      rule = FactoryBot.build(:automation_rule, params)
      expect(rule.valid?).to be false
      expect(rule.errors.messages[:conditions]).to eq(['Automation conditions should have query operator.'])
    end

    it 'allows labels as a valid condition attribute' do
      params[:conditions] = [
        {
          attribute_key: 'labels',
          filter_operator: 'equal_to',
          values: ['bug'],
          query_operator: nil
        }
      ]
      rule = FactoryBot.build(:automation_rule, params)
      expect(rule.valid?).to be true
    end

    it 'validates label condition operators' do
      params[:conditions] = [
        {
          attribute_key: 'labels',
          filter_operator: 'is_present',
          values: [],
          query_operator: nil
        }
      ]
      rule = FactoryBot.build(:automation_rule, params)
      expect(rule.valid?).to be true
    end

    it 'allows private_note as a valid condition attribute' do
      params[:conditions] = [
        {
          attribute_key: 'private_note',
          filter_operator: 'equal_to',
          values: [true],
          query_operator: nil
        }
      ]
      rule = FactoryBot.build(:automation_rule, params)
      expect(rule.valid?).to be true
    end
  end

  describe 'reauthorizable' do
    context 'when prompt_reauthorization!' do
      it 'marks the rule inactive' do
        rule = create(:automation_rule)
        expect(rule.active).to be true
        rule.prompt_reauthorization!
        expect(rule.active).to be false
      end
    end

    context 'when reauthorization_required?' do
      it 'unsets the error count if conditions are updated' do
        rule = create(:automation_rule)
        rule.prompt_reauthorization!
        expect(rule.reauthorization_required?).to be true

        rule.update!(conditions: [{ attribute_key: 'browser_language', filter_operator: 'equal_to', values: ['en'], query_operator: 'AND' }])
        expect(rule.reauthorization_required?).to be false
      end

      it 'will not unset the error count if conditions are not updated' do
        rule = create(:automation_rule)
        rule.prompt_reauthorization!
        expect(rule.reauthorization_required?).to be true

        rule.update!(name: 'Updated name')
        expect(rule.reauthorization_required?).to be true
      end
    end
  end

  describe 'schedule validations' do
    let(:account) { create(:account) }
    let(:base_conditions) do
      [{ 'attribute_key' => 'status', 'filter_operator' => 'equal_to', 'values' => ['open'], 'query_operator' => nil }]
    end
    let(:base_actions) do
      [{ 'action_name' => 'assign_team', 'action_params' => [] }]
    end

    def build_rule(attrs = {})
      AutomationRule.new(
        {
          account: account,
          name: 'Test rule',
          event_name: 'conversation_created',
          conditions: base_conditions,
          actions: base_actions,
          active: true
        }.merge(attrs)
      )
    end

    context 'when event_name is time_elapsed' do
      it 'is valid with a valid anchor and positive duration' do
        rule = build_rule(
          event_name: 'time_elapsed',
          schedule_anchor: 'waiting_since',
          schedule_duration_minutes: 60
        )
        expect(rule).to be_valid
      end

      it 'is invalid without a schedule_anchor' do
        rule = build_rule(
          event_name: 'time_elapsed',
          schedule_anchor: nil,
          schedule_duration_minutes: 60
        )
        expect(rule).not_to be_valid
        expect(rule.errors[:schedule_anchor]).to be_present
      end

      it 'is invalid with an unrecognised schedule_anchor' do
        rule = build_rule(
          event_name: 'time_elapsed',
          schedule_anchor: 'not_a_real_anchor',
          schedule_duration_minutes: 60
        )
        expect(rule).not_to be_valid
        expect(rule.errors[:schedule_anchor]).to be_present
      end

      it 'is invalid without schedule_duration_minutes' do
        rule = build_rule(
          event_name: 'time_elapsed',
          schedule_anchor: 'conversation_created',
          schedule_duration_minutes: nil
        )
        expect(rule).not_to be_valid
        expect(rule.errors[:schedule_duration_minutes]).to be_present
      end

      it 'is invalid when schedule_duration_minutes is zero' do
        rule = build_rule(
          event_name: 'time_elapsed',
          schedule_anchor: 'conversation_created',
          schedule_duration_minutes: 0
        )
        expect(rule).not_to be_valid
        expect(rule.errors[:schedule_duration_minutes]).to be_present
      end

      it 'is invalid when schedule_duration_minutes is negative' do
        rule = build_rule(
          event_name: 'time_elapsed',
          schedule_anchor: 'conversation_created',
          schedule_duration_minutes: -10
        )
        expect(rule).not_to be_valid
        expect(rule.errors[:schedule_duration_minutes]).to be_present
      end

      it 'accepts all valid schedule anchors' do
        AutomationRule::VALID_SCHEDULE_ANCHORS.each do |anchor|
          rule = build_rule(
            event_name: 'time_elapsed',
            schedule_anchor: anchor,
            schedule_duration_minutes: 30
          )
          expect(rule).to be_valid, "Expected anchor '#{anchor}' to be valid but got: #{rule.errors.full_messages}"
        end
      end
    end

    context 'when event_name is not time_elapsed' do
      it 'is invalid when schedule_anchor is set on a non-timer event' do
        rule = build_rule(
          event_name: 'conversation_created',
          schedule_anchor: 'waiting_since'
        )
        expect(rule).not_to be_valid
        expect(rule.errors[:schedule_anchor]).to be_present
      end

      it 'is invalid when schedule_duration_minutes is set on a non-timer event' do
        rule = build_rule(
          event_name: 'conversation_created',
          schedule_duration_minutes: 60
        )
        expect(rule).not_to be_valid
        expect(rule.errors[:schedule_duration_minutes]).to be_present
      end

      it 'is valid without schedule fields' do
        rule = build_rule(event_name: 'conversation_created')
        expect(rule).to be_valid
      end
    end
  end
end
