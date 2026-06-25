require 'rails_helper'

RSpec.describe '/api/v1/auth/capabilities', type: :request do
  describe 'GET /api/v1/auth/capabilities' do
    it 'returns 200 without authentication' do
      get '/api/v1/auth/capabilities'
      expect(response).to have_http_status(:ok)
    end

    it 'always includes email in allowed_login_methods' do
      get '/api/v1/auth/capabilities'
      expect(response.parsed_body['allowed_login_methods']).to include('email')
    end

    context 'when google oauth is disabled' do
      before { allow(GlobalConfigService).to receive(:load).with('ENABLE_GOOGLE_OAUTH_LOGIN', anything).and_return('false') }

      it 'does not include google_oauth' do
        get '/api/v1/auth/capabilities'
        expect(response.parsed_body['allowed_login_methods']).not_to include('google_oauth')
      end
    end

    context 'when SAML is enabled on an enterprise plan' do
      before do
        allow(ChatwootApp).to receive(:enterprise?).and_return(true)
        allow(GlobalConfigService).to receive(:load).with('ENABLE_SAML_SSO_LOGIN', anything).and_return('true')
        allow(InstallationConfig).to receive(:find_by).with(name: 'INSTALLATION_PRICING_PLAN').and_return(
          double(value: 'enterprise')
        )
      end

      it 'includes saml in allowed_login_methods' do
        get '/api/v1/auth/capabilities'
        expect(response.parsed_body['allowed_login_methods']).to include('saml')
      end
    end

    context 'when on community plan' do
      before { allow(ChatwootApp).to receive(:enterprise?).and_return(false) }

      it 'does not include saml' do
        get '/api/v1/auth/capabilities'
        expect(response.parsed_body['allowed_login_methods']).not_to include('saml')
      end
    end
  end
end
