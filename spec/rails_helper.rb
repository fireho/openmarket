# For the specs that boot a host: spec/models, spec/requests, spec/routing.
# The host is spec/dummy; the database is a real Mongo.
#
#   MONGO_TEST_DB=openmarket_<who> bin/rspec spec/models spec/requests spec/routing
ENV["RAILS_ENV"] ||= "test"
require_relative "dummy/config/environment"

require "rspec/rails"
require "mongoid-rspec"
require "fabrication"
require "fabrication/syntax/make"
require "faker"

Fabrication.configure { |config| config.path_prefix = File.expand_path("..", __dir__) }

RSpec.configure do |config|
  config.include Mongoid::Matchers, type: :model
  config.infer_spec_type_from_file_location!

  # Every run rebuilds the indexes from the models, so the unique ones are
  # what a spec runs into. Each example starts empty, the indexes kept.
  config.before(:suite) do
    Mongoid.purge!
    Rails.application.eager_load!
    Mongoid::Tasks::Database.create_indexes
  end
  config.before { Mongoid.truncate! }
  config.after { I18n.locale = I18n.default_locale }
end
