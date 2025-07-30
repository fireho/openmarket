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

  belongs_to :brand, optional: true

  validates :name, presence: true
  validates :code, uniqueness: true, allow_blank: true

  # Creates a unique index on the name and brand fields
  index({ code: 1 }, { unique: true, sparse: true })
  index({ name: 1, brand: 1 })

  def self.search(term)
    return all unless term.present?
    where(name: /#{term}/i).or(brand: /#{term}/i).or(code: /#{term}/i)
  end

  # Import a line of written data
  # Egs:
  # Cerveja Patagonia LATA 350ml  { name: "Cerveja Patagonia", kind: "beer", pack: "can", size: 350, acl: 4.8 }
  # Cerveja Patagonia Lata 269 ml  { name: "Cerveja Patagonia", kind: "beer", pack: "can", size: 269, acl: 4.8 }
  # Cerveja Amstel - GRF 330ml  { name: "Cerveja Amstel", kind: "beer", pack: "grf", size: 330, acl: 5.0 }
  # Cerveja Amstel GRF 550 ml  { name: "Cerveja Amstel", kind: "beer", pack: "grf", size: 550, acl: 5.0 }
  # Energético Furioso PET 2000 ml  { name: "Energético Furioso", kind: "energy", pack: "pet", size: 2000, acl: 0.0 }
  # Refrigerante Furioso-Pet 200ml  { name: "Refrigerante Furioso-Pet", kind: "soda", pack: "pet", size: 200, acl: 0.0 }
  def self.import(line)
    #
    self.class.create!()
  end
end