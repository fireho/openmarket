# A stand-in for Enumere, the part of it openmarket reads, until Enumere is
# published. A host that has the real one never loads this file.
#
#   enumere :kinds, default: :beer
#   kind :beer, acl: 5
#
#   Drink.new.kind              # => "beer"   a String field
#   Drink.kinds                 # => { "beer" => { name: "Cerveja", acl: 5 } }
#   Drink.kinds_select          # => [["Cerveja", "beer"]]
#   Drink.new.kind_name         # => "Cerveja"  mongoid.attributes.drink.kind_enums.beer
#   Drink.new.kind_data[:acl]   # => 5
module Enumere
  extend ActiveSupport::Concern

  included do
    class_attribute :_enumere_definitions, instance_writer: false, default: {}
  end

  class_methods do
    def enumere(name, default: nil)
      member = name.to_s.singularize

      field member.to_sym, type: String, default: default

      define_singleton_method(member) do |key, **options|
        definitions = _enumere_definitions.deep_dup
        (definitions[name] ||= {})[key.to_s] = options
        self._enumere_definitions = definitions
      end

      define_singleton_method(name) do
        scope = "mongoid.attributes.#{model_name.i18n_key}.#{member}_enums"
        _enumere_definitions.fetch(name, {}).to_h do |key, options|
          [ key, { name: I18n.t("#{scope}.#{key}", default: key.humanize) }.merge(options) ]
        end
      end

      define_singleton_method("#{name}_select") { public_send(name).map { |key, data| [ data[:name], key ] } }

      define_method("#{member}_data") { self.class.public_send(name)[public_send(member).to_s] }
      define_method("#{member}_name") { public_send("#{member}_data")&.dig(:name) }
    end
  end
end
