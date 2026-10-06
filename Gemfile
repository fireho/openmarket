source "https://rubygems.org"

# Specify your gem's dependencies in openmarket.gemspec.
gemspec

gem "mongoid"

# Omakase Ruby styling [https://github.com/rails/rubocop-rails-omakase/]
gem "rubocop-rails-omakase", require: false

# The plain-Ruby specs (spec/lib) need no Rails and no Mongo: bin/rspec spec/lib
gem "rspec", group: :test

# The host specs (spec/models, spec/requests, spec/routing) boot spec/dummy,
# a host as small as one gets, on a real Mongo. What a fire host brings and
# the engine leans on, the dummy brings too — at the versions fire pins.
group :test do
  gem "rspec-rails"
  gem "mongoid-rspec"
  gem "fabrication"
  gem "faker"
  gem "strip_attributes"
  gem "pagy", ">= 43"
  gem "money"
  gem "jbuilder"
end

# Start debugger with binding.b [https://github.com/ruby/debug]
# gem "debug", ">= 1.0.0"
