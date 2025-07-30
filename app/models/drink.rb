#
# What to drink... 🍺 🍷 🍸 🍹 🥃
#
class Drink < Item

  enumere :kinds, default: :beer
  kind :beer, acl: 5
  kind :water, acl: 0
  kind :whisky, acl: 40
  kind :gin, acl: 40
  kind :rum, acl: 40
  kind :wine, acl: 14
  kind :vodka, acl: 40
  kind :cognac, acl: 40
  kind :liquor, acl: 40
  kind :tequila, acl: 40
  kind :soda, acl: 0
  kind :juice, acl: 0
  kind :energy, acl: 0

  enumere :packs, default: :can
  pack :can, icon: "󰑌"
  pack :grf, icon: ""
  pack :pet, icon: "󱍣"
  pack :kit, icon: ""
  pack :mix, icon: ""

  field :size,  type: Integer # in milliliters
  field :acl,   type: Integer # Alcohol in percentage

  validates :kind, inclusion: { in: Drink.kinds.keys }, allow_nil: true
  validates :pack, inclusion: { in: Drink.packs.keys }, allow_nil: true

  # Validates that size and alcohol are positive integers
  validates :acl,  numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :size, numericality: { only_integer: true, greater_than: 0 }


  # Prints alcohol content nice with a percent sign
  def alcohol
    "#{acl}%"
  end

  # Prints size nice with a milliliter sign
  def size_ml
    "#{size}ml"
  end

  def acl=(value)
    self[:acl] = value.to_s.gsub(/[^0-9]/, "").to_i
  end

  # For fun let's calculate how much you pay for alcohol
  # Expects price to be a Money object or a numeric value in the same currency/unit.
  def acl_price(price_obj)
    return 0 if size.zero? || acl.zero?
    price = price_obj.is_a?(Money) ? price_obj : Money.new(price_obj.to_i) # Assuming default currency
    # This gives you the price per milliliter of pure alcohol
    # Ensure calculations are done carefully, especially if price_obj is Money
    # (price_obj.cents / (size * acl / 100.0)).to_i will give cents
    (price.cents / (size * (acl / 100.0))) # Example: returns cents
  end

  def self.icon
    "".freeze # 󰂘  󱄖  󰗲
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
