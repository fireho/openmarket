class Product
  include Mongoid::Document
  include Mongoid::Timestamps
  include Enumere

  strip_attributes

  field :name,  type: String, localize: true
  field :info,  type: String, localize: true

  field :code,  type: String  # barcode, ean, isbn, issn
  field :sku,   type: String  # internal

  field :uses,  type: Integer # lets count uses so we put on top

  # What the open catalogue knows about a thing beyond its name.
  field :image,     type: String          # a picture's URL — the dump carries links, never pictures
  field :quantity,  type: String          # as the label says it: "350 ml", "6 x 330 ml"
  field :countries, type: Array, default: [] # where it is sold, as slugs: "brazil"
  field :tags,      type: Array, default: [] # the source's categories, as slugs: "beers", "lagers"
  field :source,    type: String          # where the row came from: "off"; nil when a person wrote it
  field :tokens,    type: Array, default: [] # its names' and brand's words, folded: what `search` matches

  belongs_to :brand, optional: true

  # Who may put this on a menu. Nothing (`org: nil`) is the shared catalogue —
  # a Brahma is a Brahma, an admin curates it, everybody selects it. An org on
  # it makes it that org's own: a recipe ("Caipirinha da Casa"), theirs to
  # write and nobody else's to see. `Product.for(org)` is both together.
  belongs_to :org, optional: true

  validates :name, presence: true
  # One barcode per owner: the shared catalogue has one Brahma, and an org's
  # own Brahma (filed before the catalogue had it) never blocks it.
  validates :code, uniqueness: { scope: :org_id }, allow_blank: true

  # What a person corrects. An import refreshes rows it wrote (`source`); once
  # someone edits one of these, the row is theirs and imports leave it alone.
  OWNED = %w[ name info code brand_id image quantity countries tags kind pack size acl ].freeze

  # Set by an importer while it writes, so its own saves do not count as edits.
  attr_accessor :importing

  # A barcode has one spelling in the catalogue (UPC-A becomes EAN-13), so the
  # uniqueness above and the scan in `lookup` mean the same thing. A code that
  # is not a barcode — an isbn-10, a house code — is left as it was typed. No
  # code is no field at all: a stored null would collide in the unique index.
  before_validation do
    if code.present? then self.code = Openmarket::Ean.normalize(code) || code
    elsif attributes.key?("code") then remove_attribute(:code)
    end
  end

  before_save { self.source = nil if source && !importing && edited? }
  before_save { self.tokens = tokenize }

  scope :shared, -> { where(org_id: nil) }
  scope :of,     ->(org) { where(org_id: org) }

  # The catalogue as one org sees it: what everybody has, plus what is theirs.
  def self.for(org)
    org ? any_of({ org_id: nil }, { org_id: org.try(:id) || org }) : shared
  end

  # Only rows with a code are in it — a missing code is not a value to be unique.
  index({ code: 1, org_id: 1 }, { unique: true, partial_filter_expression: { code: { "$type" => "string" } } })
  index({ name: 1, brand_id: 1 })
  index({ brand_id: 1 }) # a brand's shelf, and `search` by brand
  index({ org_id: 1, name: 1 }) # an org reading its own shelf
  index({ tokens: 1 }) # `search`

  # One collection (STI), so ask the document, not its class name.
  def drink? = is_a?(Drink)
  def food?  = is_a?(Food)

  # A name in any language beats none: a row imported as { "es" => "Cerveza
  # Quilmes" } still reads "Cerveza Quilmes" where the locale is pt.
  def name = super.presence || name_translations&.values&.find(&:present?)

  # The brand as a form writes it: a name. Found however it was cased or
  # accented, made when nobody has it yet; blank (or only invisible characters)
  # takes the brand off. A new brand is saved even if the product then is not:
  # it is a real name someone typed, and the next try finds it.
  def brand_name = brand&.name

  def brand_name=(name)
    name = name.to_s.squish
    self.brand = Brand.key_for(name) && (Brand.named(name) || new_brand(name))
  end

  # The scan: a barcode in any spelling — UPC-A, EAN-13, with spaces — and the
  # one product it names, or nil. With `org`, that org's own comes first.
  #
  #   Product.lookup("7 891991 010023")   # => the Brahma
  def self.lookup(code, org: nil)
    return if code.to_s.strip.empty?

    spellings = Openmarket::Ean.variants(code)
    spellings = [ code.to_s.strip ] if spellings.empty?
    self.for(org).where(code: { "$in" => spellings }).order_by(org_id: -1).first
  end

  # What someone typing wants: every word a prefix of a word in the name (in
  # any language) or the brand, accents and case aside — "antar orig" finds
  # "Antártica Original"; or the start of a code; or a brand's name. Each
  # clause is a prefix on an index, so it stays fast on a big catalogue.
  # The term is text, not a pattern: "(" is a typo, not a regexp error.
  def self.search(term)
    return all unless term.present?

    text = term.to_s.strip
    words = Openmarket::Text.tokens(text)
    brands = Brand.where(key: /\A#{Regexp.escape(Openmarket::Text.fold(text))}/).pluck(:_id)

    clauses = [ { code: /\A#{Regexp.escape(text.delete(' '))}/ }, { brand_id: { "$in" => brands } } ]
    clauses << { tokens: { "$all" => words.map { |word| /\A#{Regexp.escape(word)}/ } } } if words.any?
    any_of(*clauses)
  end

  # Rows saved before `tokens` existed get theirs, without counting as edits.
  def self.backfill_tokens
    any_of({ tokens: nil }, { tokens: [] }).each { |product| product.set(tokens: product.tokenize) }
  end

  def tokenize = Openmarket::Text.tokens(name_translations&.values, brand&.name)

  # Did a person change what the row says? Not blank to blank, and not a
  # default Mongoid fills into a field the stored row lacks (it reports those
  # as changes the moment a row is loaded).
  def edited?
    changes.any? do |field, (was, now)|
      next false unless OWNED.include?(field)
      next false if was.blank? && now.blank?

      !(was.nil? && now == self.class.fields[field]&.default_val)
    end
  end

  private

  # Two people adding one new brand at once: the second save is refused, by
  # the uniqueness check or, when they truly overlap, by the unique key index.
  # The brand the first one saved is the second one's too. A refusal with no
  # such brand is something else, and is raised.
  def new_brand(name)
    Brand.create!(name: name)
  rescue Mongoid::Errors::Validations, Mongo::Error::OperationFailure
    Brand.named(name) or raise
  end
end
