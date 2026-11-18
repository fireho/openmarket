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
  field :aliases,  type: Array, default: [] # the keys of names it had: imports still spell it the old way

  # Who owns it, as Product's org_id: nothing is the shared catalogue's (an
  # import's, a dump's, every org's to pick); an id makes it that org's alone —
  # a market's own label, a local maker. An id, not an association: the
  # engine names no Org class.
  field :org_id, type: Object

  # A brand with products stays: one slip of a button would leave them all
  # without one. Move them to another brand first.
  has_many :products, dependent: :restrict_with_error

  # `info` is the one line about it. Nice to have, never a reason to refuse a
  # brand: an import of thousands has a name and nothing else.
  # One name per owner: two orgs may each have "Da Casa". The unique key index
  # is what holds it ({ key, org_id }: the key is the name folded); a brand
  # from before keys has none, and `backfill_keys` checks it per owner too.
  validates :name, presence: true, uniqueness: { scope: :org_id }
  validates :key, uniqueness: { scope: :org_id }, allow_nil: true # "Antártica" is taken when "Antartica" is
  # An org's brand never shadows the catalogue's: whoever types "brahma" gets
  # the shared Brahma. One way only: a shared brand (an import, a restore)
  # still saves over an org's name, and that org's brand stays editable.
  validate :shared_key_free, if: -> { org_id && key && (new_record? || key_changed? || org_id_changed?) }
  # A brand changes owner only with no other owner's product on it: moved
  # away, a shared product would point at an org's label (Product's own check,
  # from this side).
  validate :products_stay, if: -> { persisted? && org_id_changed? }

  before_validation { self.key = self.class.key_for(name) }
  # Renamed — "Antartica" corrected to "Antarctica" — the brand is still what
  # the next import calls "Antartica": the old key stays as an alias, so the
  # import finds this brand instead of making the misspelling again.
  before_update do
    if key_changed? && key_was.present?
      self.aliases = ((aliases || []) | [ key_was ]) - [ key ]
    end
  end
  before_validation { self.country = country&.upcase } # "br" typed is "BR", as ISO and Wikidata write it

  # A product's search words hold its brand's (Product#tokens). Renamed to
  # another key, the brand takes its products' words along: written straight,
  # as `backfill_tokens` does, so it is no edit of theirs and imports still
  # refresh them. Only the key matters: "BRAHMA" to "Brahma" folds the same.
  after_update do
    products.each { |product| product.set(tokens: product.tokenize) } if saved_change_to_attribute?(:key)
  end

  scope :shared, -> { where(org_id: nil) }
  scope :of,     ->(org) { where(org_id: org.try(:id) || org) }

  # The brands one org may pick: the shared catalogue's, plus its own.
  def self.for(org)
    org ? any_of({ org_id: nil }, { org_id: org.try(:id) || org }) : shared
  end

  # One key per owner, only where there is a key (sparse on a compound index
  # would still index a brand without one). `$gt ""` because an equality on
  # key implies it, so `named` and the uniqueness and shadow checks may read
  # it. A validated save never stores "" (`key_for` gives nil for blank).
  index({ key: 1, org_id: 1 }, { unique: true, partial_filter_expression: { key: { "$gt" => "" } } })
  # `starting_with`: a prefix regex implies no partial filter, so without
  # this plain one it scans the collection.
  index({ org_id: 1, key: 1 })
  index({ name: 1 })
  index({ wikidata: 1 }, { sparse: true })
  index({ aliases: 1 })

  # A name as the brand stores it, nil for blank. strip_attributes also takes
  # a pasted BOM or zero-width space off the ends, which `squish` and `fold`
  # keep: looked up with them, "Brahma\u200B" misses the "Brahma" it then
  # clashes with on save. Scrubbed first, as `fold` does: a bad byte would
  # raise in strip_attributes.
  def self.clean(name) = StripAttributes.strip(name.to_s.scrub(""))

  def self.key_for(name) = Openmarket::Text.fold(clean(name)).presence

  # Brands made before `key` existed get theirs. Two spellings of one name in
  # one owner cannot both have it, nor an org's spelling of a shared one (it
  # would shadow it): the later ones are returned, for a person to merge.
  def self.backfill_keys
    clashes = []
    where(key: nil).each do |brand|
      key = key_for(brand.name) or next
      if where(key: key, org_id: brand.org_id).exists? || (brand.org_id && shared.where(key: key).exists?)
        clashes << brand.name
      else brand.set(key: key)
      end
    end
    clashes
  end

  # The brand a written name means, in whatever case and accents it came in.
  # Brands made before `key` existed have none, so the exact name is the
  # second try. Either way it is the brand a save of that name would clash
  # with. With `org`, that org's own first, then the shared one; without, the
  # shared catalogue only. Never another org's.
  def self.named(name, org: nil)
    key = key_for(name) or return
    scopes = org ? [ of(org), shared ] : [ shared ]
    scopes.each do |scope|
      found = scope.where(key: key).first || scope.where(aliases: key).first || scope.where(name: clean(name)).first
      return found if found
    end
    nil
  end

  # What someone typing a brand wants, over Brand.for(org): the brands whose
  # name starts with it. Without an org, the shared catalogue.
  def self.search(term, org: nil) = self.for(org).starting_with(term)

  # The brands whose name starts with `term`, accents and case aside — "antar"
  # finds "Antártica" — on whatever scope it is called (a controller's
  # `brands`). A prefix on the key's index, and the term is text, never a
  # pattern. Nothing typed is every brand of the scope. By key, the order
  # people read names in: "ambev" among the A's, not after "Zé" as a sort on
  # the stored name would put it.
  def self.starting_with(term)
    key = key_for(term)
    (key ? where(key: /\A#{Regexp.escape(key)}/) : all).order_by(key: 1, name: 1)
  end

  private

  def shared_key_free
    errors.add(:name, :taken) if Brand.shared.where(key: key, _id: { "$ne" => id }).exists? # itself, moving in, shadows nothing
  end

  def products_stay
    errors.add(:products, :other_owner) if org_id && products.where(org_id: { "$ne" => org_id }).exists?
  end
end
