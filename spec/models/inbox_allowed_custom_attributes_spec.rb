# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Inbox#allowed_custom_attribute_definitions' do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }

  let!(:attr_service_type) do
    create(:custom_attribute_definition, account: account, attribute_key: 'service_type',
                                         attribute_display_name: 'Service Type', attribute_model: 'conversation_attribute')
  end
  let!(:attr_issue_category) do
    create(:custom_attribute_definition, account: account, attribute_key: 'issue_category',
                                         attribute_display_name: 'Issue Category', attribute_model: 'conversation_attribute')
  end
  let!(:attr_priority_level) do
    create(:custom_attribute_definition, account: account, attribute_key: 'priority_level',
                                         attribute_display_name: 'Priority Level', attribute_model: 'conversation_attribute')
  end

  context 'when allowed_custom_attribute_keys is empty' do
    it 'returns all conversation attributes' do
      expect(inbox.allowed_custom_attribute_definitions).to contain_exactly(attr_service_type, attr_issue_category, attr_priority_level)
    end
  end

  context 'when allowed_custom_attribute_keys is set' do
    before { inbox.update!(allowed_custom_attribute_keys: %w[service_type issue_category]) }

    it 'returns only the specified attributes' do
      expect(inbox.allowed_custom_attribute_definitions).to contain_exactly(attr_service_type, attr_issue_category)
    end

    it 'excludes attributes not in the list' do
      expect(inbox.allowed_custom_attribute_definitions).not_to include(attr_priority_level)
    end
  end

  context 'when allowed_custom_attribute_keys contains a non-existent key' do
    before { inbox.update!(allowed_custom_attribute_keys: %w[service_type nonexistent]) }

    it 'returns only existing attributes that match' do
      expect(inbox.allowed_custom_attribute_definitions).to contain_exactly(attr_service_type)
    end
  end
end
