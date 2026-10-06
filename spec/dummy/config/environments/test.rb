Rails.application.configure do
  config.cache_classes = true
  config.action_controller.allow_forgery_protection = false
  config.active_support.deprecation = :stderr
end
