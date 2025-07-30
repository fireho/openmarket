Fabricator(:food) do
  name { Faker::Food.dish }
  kind { Food.kinds.keys.sample }
  pack { Food.packs.keys.sample }
  code { Faker::Barcode.ean(13) }
  brand { Faker::Company.name }
  size  { Faker::Number.between(from: 50, to: 1000) }
end
