#
# What to drink... 🍺 🍷 🍸 🍹 🥃
#
class Drink < Product

  enumere :kinds, default: :beer
  kind :beer, acl: 5
  kind :water, acl: 0
  kind :whisky, acl: 40
  kind :gin, acl: 40
  kind :rum, acl: 40
  kind :cachaca, acl: 40
  kind :wine, acl: 14
  kind :vodka, acl: 40
  kind :cognac, acl: 40
  kind :cider, acl: 5
  kind :liquor, acl: 40
  kind :tequila, acl: 40
  kind :soda, acl: 0
  kind :juice, acl: 0
  kind :energy, acl: 0
  kind :mixed, acl: 5 # ready-to-drink: alcopops, hard seltzers, premixed cocktails
  kind :tea, acl: 0   # iced tea, ready to drink

  enumere :packs, default: :can
  pack :can, icon: "󰑌"
  pack :grf, icon: ""
  pack :pet, icon: "󱍣"
  pack :kit, icon: ""
  pack :mix, icon: ""

  field :size,  type: Integer # in milliliters
  field :acl,   type: Float   # Alcohol by volume, in percent: 4.8, 40. nil when nobody knows

  validates :kind, inclusion: { in: Drink.kinds.keys }, allow_nil: true
  validates :pack, inclusion: { in: Drink.packs.keys }, allow_nil: true

  # Unknown is not zero: a beer with no label data is not a 0% beer.
  validates :acl,  numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 100 }, allow_nil: true
  # A recipe has no bottle — nil size is fine, zero is not.
  validates :size, numericality: { only_integer: true, greater_than: 0 }, allow_blank: true # a form sends "", not nil


  # Prints alcohol content nice with a percent sign: "4.8%", "40%"
  def alcohol
    "#{format('%g', acl)}%" if acl
  end

  # Prints size nice with a milliliter sign
  def size_ml
    "#{size}ml"
  end

  # "7.6%", "7,6", 7.6, 40 — all land as the number they say, to two decimals;
  # blank lands as nil. Stripping every non-digit used to read 7.6% as 76, a
  # beer three times a whisky.
  def acl=(value)
    num = value.to_s.tr(",", ".")[/\d*\.?\d+/]
    self[:acl] = num&.to_f&.round(2)
  end

  # For fun let's calculate how much you pay for alcohol
  # Expects price to be a Money object or a numeric value in the same currency/unit.
  def acl_price(price_obj)
    return 0 if size.to_i.zero? || acl.to_f.zero?
    price = price_obj.is_a?(Money) ? price_obj : Money.new(price_obj.to_i) # Assuming default currency
    # This gives you the price per milliliter of pure alcohol
    # Ensure calculations are done carefully, especially if price_obj is Money
    # (price_obj.cents / (size * acl / 100.0)).to_i will give cents
    (price.cents / (size * (acl / 100.0))) # Example: returns cents
  end

  def self.icon
    "".freeze # 󰂘  󱄖  󰗲
  end
end
