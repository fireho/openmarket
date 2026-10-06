class Brand
  include Mongoid::Document
  include Mongoid::Timestamps

  # A form sends "" for every field left empty. Stored, it would read as
  # something known: `where(wikidata: nil)` would skip a brand nobody linked.
  strip_attributes

  field :name, type: String
  field :info, type: String

  # What the open catalogue knows about a maker.
  field :key,      type: String # the name folded for lookup: "Antártica" and "ANTARTICA " meet
  field :wikidata, type: String # "Q1234" — the same brand, everywhere
  field :country,  type: String # where it is from: ISO 3166 alpha-2, "BR"
  field :site,     type: String
  field :logo,     type: String # a URL
  field :source,   type: String # "off", "wikidata"; nil when typed by hand

  # A brand with products stays: one slip of a button would leave them all
  # without one. Move them to another brand first.
  has_many :products, dependent: :restrict_with_error

  # `info` is the one line about it. Nice to have, never a reason to refuse a
  # brand: an import of thousands has a name and nothing else.
  validates :name, presence: true, uniqueness: true
  validates :key, uniqueness: true, allow_nil: true # "Antártica" is taken when "Antartica" is

  before_validation { self.key = self.class.key_for(name) }
  before_validation { self.country = country&.upcase } # "br" typed is "BR", as ISO and Wikidata write it

  # A product's search words hold its brand's (Product#tokens). Renamed to
  # another key, the brand takes its products' words along: written straight,
  # as `backfill_tokens` does, so it is no edit of theirs and imports still
  # refresh them. Only the key matters: "BRAHMA" to "Brahma" folds the same.
  after_update do
    products.each { |product| product.set(tokens: product.tokenize) } if saved_change_to_attribute?(:key)
  end

  index({ key: 1 }, { unique: true, sparse: true })
  index({ name: 1 })
  index({ wikidata: 1 }, { sparse: true })

  # A name as the brand stores it, nil for blank. strip_attributes also takes
  # a pasted BOM or zero-width space off the ends, which `squish` and `fold`
  # keep: looked up with them, "Brahma\u200B" misses the "Brahma" it then
  # clashes with on save. Scrubbed first, as `fold` does: a bad byte would
  # raise in strip_attributes.
  def self.clean(name) = StripAttributes.strip(name.to_s.scrub(""))

  def self.key_for(name) = Openmarket::Text.fold(clean(name)).presence

  # Brands made before `key` existed get theirs. Two spellings of one name
  # cannot both have it: the later ones are returned, for a person to merge.
  def self.backfill_keys
    clashes = []
    where(key: nil).each do |brand|
      key = key_for(brand.name) or next
      if where(key: key).exists? then clashes << brand.name
      else brand.set(key: key)
      end
    end
    clashes
  end

  # The brand a written name means, in whatever case and accents it came in.
  # Brands made before `key` existed have none, so the exact name is the second try.
  # Either way it is the brand a save of that name would clash with.
  def self.named(name)
    key = key_for(name) or return
    where(key: key).first || where(name: clean(name)).first
  end

  # What someone typing a brand wants: the brands whose name starts with it,
  # accents and case aside — "antar" finds "Antártica". A prefix on the key's
  # index, and the term is text, never a pattern. Nothing typed is every brand.
  # By key, the order people read names in: "ambev" among the A's, not after
  # "Zé" as a sort on the stored name would put it.
  def self.search(term)
    key = key_for(term)
    (key ? where(key: /\A#{Regexp.escape(key)}/) : all).order_by(key: 1, name: 1)
  end
end
