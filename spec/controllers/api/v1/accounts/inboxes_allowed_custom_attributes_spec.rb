# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Inboxes API - allowed_custom_attribute_keys', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:inbox) { create(:inbox, account: account) }

  describe 'PATCH /api/v1/accounts/{account_id}/inboxes/{id}' do
    context 'when setting allowed_custom_attribute_keys' do
      it 'updates the allowed keys' do
        patch "/api/v1/accounts/#{account.id}/inboxes/#{inbox.id}",
              headers: admin.create_new_auth_token,
              params: { allowed_custom_attribute_keys: %w[service_type issue_category] },
              as: :json

        expect(response).to have_http_status(:success)
        expect(inbox.reload.allowed_custom_attribute_keys).to eq(%w[service_type issue_category])
      end

      it 'returns the allowed keys in the response' do
        inbox.update!(allowed_custom_attribute_keys: %w[service_type])

        get "/api/v1/accounts/#{account.id}/inboxes",
            headers: admin.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:success)
        inbox_data = response.parsed_body['payload'].find { |i| i['id'] == inbox.id }
        expect(inbox_data['allowed_custom_attribute_keys']).to eq(%w[service_type])
      end

      it 'clears the allowed keys when set to empty array' do
        inbox.update!(allowed_custom_attribute_keys: %w[service_type])

        patch "/api/v1/accounts/#{account.id}/inboxes/#{inbox.id}",
              headers: admin.create_new_auth_token,
              params: { allowed_custom_attribute_keys: [] },
              as: :json

        expect(response).to have_http_status(:success)
        expect(inbox.reload.allowed_custom_attribute_keys).to eq([])
      end
    end
  end
end
