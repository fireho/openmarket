# One product, two kinds of it. Drink and Food ARE Products (STI, one
# collection), so they inherit the fabricator and add what is theirs — a spec
# says `Drink.make(kind: "beer")` and nothing more. Kinds and packs come from
# the model, never a literal: Enumere's keys are what the inclusion validates.
#
# No `brand`: it is a Brand relation now, not a string, and it's optional.
Fabricator(:product) do
  name { Faker::Commerce.product_name }
  code { Faker::Barcode.ean(13) }
end

Fabricator(:brand) do
  name { Faker::Company.name }
  info { Faker::Company.catch_phrase }
end

Fabricator(:drink, from: :product, class_name: "Drink") do
  name { Faker::Beer.name }
  kind { Drink.kinds.keys.sample }
  pack { Drink.packs.keys.sample }
  acl  { Faker::Beer.alcohol } # "7.6%" — Drink#acl= rounds it to 8
  size { Faker::Number.between(from: 50, to: 500) } # ml
end

# Food has kinds, no packs.
Fabricator(:food, from: :product, class_name: "Food") do
  name { Faker::Food.dish }
  kind { Food.kinds.keys.sample }
  size { Faker::Number.between(from: 50, to: 1000) } # g
end
