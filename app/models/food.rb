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
  validates :size, numericality: { only_integer: true, greater_than: 0 }, allow_blank: true # a form sends "", not nil
  # "garrafa" is no size. Mongoid casts it to nil, which allow_blank lets by.
  validate { errors.add(:size, :not_a_number) if size.nil? && size_before_type_cast.present? }

  # Prints size nice with a gram sign
  def size_g
    "#{size}g" if size
  end

  def self.icon
    "󰌹".freeze # 󰌹 󰙎 󰂖
  end
end
