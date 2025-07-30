class Food < Product

  enumere :kinds, default: :fast
  kind :fast, acl: 0
  kind :burger, acl: 0
  kind :pizza, acl: 0
  kind :pasta, acl: 0
  kind :sushi, acl: 0
  kind :dessert, acl: 0
  kind :snack, acl: 0
  kind :meat, acl: 0

  field :size,  type: Integer # in grams

  validates :kind, inclusion: { in: Food.kinds.keys }, allow_nil: true
  validates :size, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true

  # Prints size nice with a gram sign
  def size_g
    "#{size}g" if size
  end

  def self.icon
    "󰌹".freeze # 󰌹 󰙎 󰂖
  end

  # Import a line of written data
  # Egs:
  # Chocolate Montanha PC 500g  { name: "Chocolate Montanha", kind: "dessert", pack: "pc", size: 500, acl: 0.0 }
  # Antipasto de Azeitona - Lata 230g  { name: "Antipasto de Azeitona", kind: "snack", pack: "can", size: 269, acl: 4.8 }
  def self.import(line)
    #
    self.class.create!()
  end
end