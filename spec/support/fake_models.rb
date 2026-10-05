# Just enough of Mongoid for the importer and the catalogue to run without a
# database: a document is a bag of attributes, `where(code: x).first` finds
# one, `save` validates like the real models do (a name; a code nobody has).
# It proves the flow — what is created, kept, refreshed — not Mongoid's API.
module Fake
  Errors = Struct.new(:full_messages)

  class Document
    def initialize(attrs = {})
      @attrs = {}
      assign(attrs)
    end

    def assign(attrs)
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
      assign(attrs)
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

    def self.named(name)
      key = Openmarket::Text.fold(name)
      rows.find { |brand| brand.key == key }
    end

    def validate
      self.key = Openmarket::Text.fold(name)
      problems = []
      problems << "Name can't be blank" if key.empty?
      problems << "Name is taken" if self.class.rows.any? { |other| !other.equal?(self) && other.key == key }
      problems
    end
  end

  class Product < Document
    FIELDS = %i[ code name_translations info_translations brand image quantity countries tags source ].freeze

    def self.rows = Fake::Product.instance_variable_get(:@rows) || Fake::Product.instance_variable_set(:@rows, [])
    def self.reset! = Fake::Product.instance_variable_set(:@rows, [])
    def self.shared = Relation.new(rows)

    def drink? = is_a?(Drink)
    def food?  = is_a?(Food)
    def brand_id = brand&.object_id
    def name = name_translations&.values&.first

    def validate
      problems = []
      problems << "Name can't be blank" if name.to_s.empty?
      if self.class.rows.any? { |other| !other.equal?(self) && other.code == code }
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
    def where(conditions) = Relation.new(rows.select { |row| conditions.all? { |key, value| row.public_send(key) == value } })
    def first = rows.first
  end

  def self.reset!
    Brand.reset!
    Product.reset!
  end

  TYPES = { "Drink" => Drink, "Food" => Food, "Product" => Product }.freeze
end
