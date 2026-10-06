# What a host's ApplicationController gives the engine's controllers.
class ApplicationController < ActionController::Base
  include Pagy::Method
end
