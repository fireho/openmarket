require "rails"
require "action_controller/railtie"
require "action_view/railtie"
require "mongoid"
require "strip_attributes"
require "pagy"
require "money"
require "jbuilder"
require "openmarket"

# The smallest host the engine runs in: what spec/models, spec/requests and
# spec/routing boot. It plays fire's part too — fire's Enumere lives in
# app/models/concerns, as a stand-in, until fire is open.
module Dummy
  class Application < Rails::Application
    config.load_defaults 8.0
    config.root = File.expand_path("..", __dir__)
    config.eager_load = false
    config.hosts.clear
    config.i18n.available_locales = %i[ en pt ]
    config.i18n.default_locale = :en
    config.action_dispatch.show_exceptions = :rescuable
    config.secret_key_base = "dummy"
    config.logger = Logger.new(nil)
  end
end
