class Api::V1::AuthController < Api::BaseController
  skip_before_action :authenticate_user!, :set_current_user, :handle_with_exception,
                     only: %i[capabilities saml_login], raise: false

  def capabilities
    render json: { allowed_login_methods: allowed_login_methods }
  end

  def saml_login
    head :not_implemented
  end

  private

  def allowed_login_methods
    methods = ['email']
    methods << 'google_oauth' if GlobalConfigService.load('ENABLE_GOOGLE_OAUTH_LOGIN', 'true').to_s != 'false'
    methods << 'saml' if ChatwootHub.pricing_plan != 'community' && GlobalConfigService.load('ENABLE_SAML_SSO_LOGIN', 'true').to_s != 'false'
    methods
  end
end
