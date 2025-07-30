# frozen_string_literal: true

require 'mongoid'


module Openmarket
  # Rails Engine
  class Engine < ::Rails::Engine
    isolate_namespace Openmarket
  end
end