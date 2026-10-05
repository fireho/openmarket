# Just enough of Mongoid for the importer and the catalogue to run without a
# database, behaving like the real models where the importer depends on it:
# a code is normalised before it is checked, a code is unique per owner (org),
# `where(code: { "$in" => [...] })` finds by any spelling, a brand made before
# keys existed has none and is found by its exact name.
# It proves the flow — what is created, kept, refreshed — not Mongoid's API.
module Fake
  Errors = Struct.new(:full_messages)

  class Document
    attr_accessor :importing

    def initialize(attrs = {})
      @attrs = {}
      assign_attributes(attrs)
    end

    def assign_attributes(attrs)
      attrs.each { |key, value| @attrs[key.to_sym] = value }
    end

    def method_missing(name, *args)
      key = name.to_s
      if key.end_with?("=") then @attrs[key.chomp("=").to_sym] = args.first
      elsif respond_to_missing?(name) then @attrs[name]
      else super
      end
    end

    def respond_to_missing?(name, include_private = false)
      @attrs.key?(name.to_sym) || self.class::FIELDS.include?(name.to_sym) || super
    end

    def update(attrs)
      assign_attributes(attrs)
      save
    end

    def errors = Errors.new(@errors || [])

    def save
      @errors = validate
      return false if @errors.any?

      rows = self.class.rows
      rows << self unless rows.include?(self)
      true
    end
  end

  class Brand < Document
    FIELDS = %i[ name info key wikidata country site logo source ].freeze

    def self.rows = (@rows ||= [])
    def self.reset! = @rows = []

    # Like Brand.named: by key, then (a brand from before keys) by exact name.
    def self.named(name)
      key = Openmarket::Text.fold(name)
      rows.find { |brand| brand.key == key } || rows.find { |brand| brand.name == name.to_s.strip }
    end

    # A brand saved before keys existed: no key, and no validation run.
    def self.legacy(name)
      new(name: name).tap { |brand| rows << brand }
    end

    def validate
      self.key = Openmarket::Text.fold(name)
      problems = []
      problems << "Name can't be blank" if key.empty?
      problems << "Key is taken" if self.class.rows.any? { |other| !other.equal?(self) && other.key == key }
      problems
    end
  end

  class Product < Document
    FIELDS = %i[ code org_id name_translations info_translations brand image quantity countries tags source ].freeze

    def self.rows = Fake::Product.instance_variable_get(:@rows) || Fake::Product.instance_variable_set(:@rows, [])
    def self.reset! = Fake::Product.instance_variable_set(:@rows, [])
    def self.shared = Relation.new(rows.select { |row| row.org_id.nil? })

    def drink? = is_a?(Drink)
    def food?  = is_a?(Food)
    def brand_id = brand&.object_id
    def name = name_translations&.values&.first

    def validate
      self.code = Openmarket::Ean.normalize(code) || code if code # as the model's before_validation
      problems = []
      problems << "Name can't be blank" if name.to_s.empty?
      if code && self.class.rows.any? { |other| !other.equal?(self) && other.code == code && other.org_id == org_id }
        problems << "Code is taken"
      end
      problems
    end
  end

  class Drink < Product
    FIELDS = (Product::FIELDS + %i[ kind pack size acl ]).freeze
  end

  class Food < Product
    FIELDS = (Product::FIELDS + %i[ kind size ]).freeze
  end

  Relation = Struct.new(:rows) do
    def where(conditions)
      Relation.new(rows.select do |row|
        conditions.all? do |key, value|
          found = row.public_send(key)
          value.is_a?(Hash) && value.key?("$in") ? value["$in"].include?(found) : found == value
        end
      end)
    end

    def first = rows.first
  end

  def self.reset!
    Brand.reset!
    Product.reset!
  end

  TYPES = { "Drink" => Drink, "Food" => Food, "Product" => Product }.freeze
end
