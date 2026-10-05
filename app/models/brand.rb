class Brand
  include Mongoid::Document
  include Mongoid::Timestamps

  field :name, type: String
  field :info, type: String

  # What the open catalogue knows about a maker.
  field :key,      type: String # the name folded for lookup: "Antártica" and "ANTARTICA " meet
  field :wikidata, type: String # "Q1234" — the same brand, everywhere
  field :country,  type: String # where it is from: ISO 3166 alpha-2, "BR"
  field :site,     type: String
  field :logo,     type: String # a URL
  field :source,   type: String # "off", "wikidata"; nil when typed by hand

  has_many :products

  # `info` is the one line about it. Nice to have, never a reason to refuse a
  # brand: an import of thousands has a name and nothing else.
  validates :name, presence: true, uniqueness: true
  validates :key, uniqueness: true, allow_nil: true # "Antártica" is taken when "Antartica" is

  before_validation { self.key = self.class.key_for(name) }

  index({ key: 1 }, { unique: true, sparse: true })
  index({ name: 1 })
  index({ wikidata: 1 }, { sparse: true })

  def self.key_for(name) = Openmarket::Text.fold(name).presence

  # The brand a written name means, in whatever case and accents it came in.
  # Brands made before `key` existed have none, so the exact name is the second try.
  def self.named(name)
    key = key_for(name) or return
    where(key: key).first || where(name: name.to_s.strip).first
  end
end
