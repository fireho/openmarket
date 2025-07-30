class Food < Item

  enumere :kinds, default: :fast
  kind :fast, acl: 5
  kind :burger, acl: 0
  kind :pizza, acl: 40
  kind :pasta, acl: 40
  kind :sushi, acl: 14
  kind :dessert, acl: 0
  kind :snack, acl: 0
  kind :meat, acl: 0

  field :size,  type: Integer # in grams

  # Import a line of written data
  # Egs:
  # Chocolate Montanha PC 500g  { name: "Chocolate Montanha", kind: "dessert", pack: "pc", size: 500, acl: 0.0 }
  # Antipasto de Azeitona - Lata 230g  { name: "Antipasto de Azeitona", kind: "snack", pack: "can", size: 269, acl: 4.8 }
  def self.import(line)
    #
    self.class.create!()
  end
end