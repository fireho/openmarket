Fabricator(:item) do
  name { Faker::Commerce.product_name }
  code { Faker::Barcode.ean(13) }
  brand { Faker::Company.name }
end
