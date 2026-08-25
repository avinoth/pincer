module Authentication
  extend ActiveSupport::Concern

  def current_user
    @current_user ||= User.find_by(id: session[:user_id])
  end

  def current_organization
    @current_organization ||= current_user&.organization
  end

  def user_signed_in?
    User.exists?(id: session[:user_id])
  end

  protected

  def sign_in(user)
    @current_user = user
    session[:user_id] = user.id
  end

  def logout
    @current_user = nil
    session.delete(:user_id)
  end

  # API-only: no flash/redirect to a login page — respond with 401 JSON.
  def authenticate_user!
    return if user_signed_in?

    render json: { error: "unauthorized" }, status: :unauthorized
  end

  # Build a redirect back to the Next.js frontend (post-OAuth landing).
  def frontend_url(query = {})
    base = ENV.fetch("FRONTEND_URL", "http://localhost:3000")
    query.present? ? "#{base}?#{query.to_param}" : base
  end
end
