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
  field :source,    type: String          # where the row came from: "off"; nil when typed by hand

  belongs_to :brand, optional: true

  # Who may put this on a menu. Nothing (`org: nil`) is the shared catalogue —
  # a Brahma is a Brahma, an admin curates it, everybody selects it. An org on
  # it makes it that org's own: a recipe ("Caipirinha da Casa"), theirs to
  # write and nobody else's to see. `Product.for(org)` is both together.
  belongs_to :org, optional: true

  validates :name, presence: true
  validates :code, uniqueness: true, allow_blank: true

  # A barcode has one spelling in the catalogue (UPC-A becomes EAN-13), so the
  # uniqueness above and the scan in `lookup` mean the same thing. A code that
  # is not a barcode — an isbn-10, a house code — is left as it was typed.
  before_validation { self.code = Openmarket::Ean.normalize(code) || code }

  scope :shared, -> { where(org_id: nil) }
  scope :of,     ->(org) { where(org_id: org) }

  # The catalogue as one org sees it: what everybody has, plus what is theirs.
  def self.for(org)
    org ? any_of({ org_id: nil }, { org_id: org.try(:id) || org }) : shared
  end

  # Creates a unique index on the name and brand fields
  index({ code: 1 }, { unique: true, sparse: true })
  index({ name: 1, brand_id: 1 })
  index({ brand_id: 1 }) # a brand's shelf, and `search` by brand
  index({ org_id: 1, name: 1 }) # an org reading its own shelf

  # One collection (STI), so ask the document, not its class name.
  def drink? = is_a?(Drink)
  def food?  = is_a?(Food)

  # The scan: a barcode in any spelling — UPC-A, EAN-13, with spaces — and the
  # one product it names, or nil. `org` widens it to that org's own as well.
  #
  #   Product.lookup("7 891991 010023")   # => the Brahma
  def self.lookup(code, org: nil)
    return if code.to_s.strip.empty?

    spellings = Openmarket::Ean.variants(code)
    spellings = [ code.to_s.strip ] if spellings.empty?
    self.for(org).where(code: { "$in" => spellings }).first
  end

  # Name, barcode, or the brand's name — brand is a relation, so it is a lookup
  # and then an id, not a regex on this document. The term is text, not a
  # pattern: "(" is a typo, not a regexp error.
  def self.search(term)
    return all unless term.present?
    like = /#{Regexp.escape(term.to_s.strip)}/i
    brands = Brand.where(name: like).pluck(:_id)
    any_of({ name: like }, { code: like }, { brand_id: { "$in" => brands } })
  end
end
