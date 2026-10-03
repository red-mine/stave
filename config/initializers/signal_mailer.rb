# Signal notification email is opt-in: nothing is sent unless
# STAVE_NOTIFY_EMAIL is set, and the SMTP connection comes from the
# environment so no credentials live in the repository.
if ENV["STAVE_SMTP_ADDRESS"].present? && !Rails.env.test?
  Rails.application.config.action_mailer.delivery_method = :smtp
  Rails.application.config.action_mailer.smtp_settings = {
    address: ENV["STAVE_SMTP_ADDRESS"],
    port: ENV.fetch("STAVE_SMTP_PORT", "587").to_i,
    user_name: ENV["STAVE_SMTP_USER"].presence,
    password: ENV["STAVE_SMTP_PASSWORD"].presence,
    authentication: ENV.fetch("STAVE_SMTP_AUTH", "plain").to_sym,
    enable_starttls_auto: ENV.fetch("STAVE_SMTP_STARTTLS", "true") == "true"
  }.compact
end
