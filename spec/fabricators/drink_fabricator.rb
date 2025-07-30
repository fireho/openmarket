# typed: false

Fabricator(:drink) do
  name { Faker::Beer.name }
  kind { Drink.kinds.keys.sample }
  pack { Drink.packs.keys.sample }
  code { Faker::Barcode.ean(13) }
  # code { Faker::Barcode.isbn } # Uncomment if you want to use ISBN instead of EAN
  # code { Faker::Barcode.issn } # Uncomment if you want to use ISSN instead of EAN
  brand { Faker::Beer.brand }
  acl   { Faker::Beer.alcohol }
  size  { Faker::Number.between(from: 50, to: 500) }
end
