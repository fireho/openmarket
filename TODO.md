# TODO — openmarket

## Holes

- [ ] FIXME views speak pt only (Nova Bebida, Salvar, Selecione…), the flash en only: every string to the locale files, where an app overrides a word app/views/products/_form.html.erb:1
- [ ] FIXME gemspec declares rails only; the models need mongoid, strip_attributes and money (acl_price), the views jbuilder, the controllers pagy openmarket.gemspec:23
- [ ] FIXME no page links with pagy 43: the views ask for `pagy_nav`, which it no longer has (`@pagy.series_nav`) app/views/products/index.html.erb:62
- [ ] FIXME `isolate_namespace` routes to Openmarket::ProductsController, which does not exist: apps draw the routes by hand (spec/dummy/config/routes.rb) lib/openmarket/engine.rb:9
- [ ] HACK Enumere stand-in for the host specs: delete when Enumere is published, depend on it spec/dummy/app/models/concerns/enumere.rb:1

## Ship it

- [ ] TODO merge to main: the monthly dump only runs on the default branch, then one workflow_dispatch .github/workflows/dump.yml:9
- [ ] TODO first CI dump runs `--wikidata` (blocked here): check brands get country, site, logo .github/workflows/dump.yml:1
- [ ] TODO the 4.5 MB snapshot in git grows the history every refresh: release asset only, or one commit per year db/openmarket.ndjson.gz
- [ ] TODO name the image license: Open Food Facts pictures are CC BY-SA 3.0 README.md:256
- [ ] TODO sha256 and a JSON Schema for the NDJSON line, published with each release lib/openmarket/dump.rb:1

## Data

- [ ] TODO Open Brewery DB (MIT): breweries as brands, with country and site lib/openmarket/
- [ ] TODO GS1 prefix to country (xoocode/gs1-prefix-ranges, CC BY 4.0): "registered in", never "made in" lib/openmarket/ean.rb
- [ ] TODO Open Food Facts daily deltas instead of the 13 GB export every month lib/openmarket/open_food_facts.rb:282
- [ ] TODO brand merge in the admin: `backfill_keys` hands clashes to a person who has no button app/models/brand.rb:65
- [ ] TODO brand owner from Wikidata P749 (Heineken owns Amstel) lib/openmarket/wikidata.rb
- [ ] TODO bar food: snacks and salty snacks from Open Food Facts as Food lib/openmarket/open_food_facts.rb
- [ ] TODO a product gone from the source is never retired: `discontinued` on restore lib/openmarket/catalogue.rb
- [ ] TODO a scan nobody knew, typed by a person: offer it back to Open Food Facts (their write API, ODbL)

## Features

- [ ] TODO `uses` is counted nowhere: count a pick, rank search by it app/models/product.rb:14
- [ ] TODO camera scan in the form (BarcodeDetector, zxing fallback) straight to lookup app/views/products/_form.html.erb
- [ ] TODO menu import: paste a menu, `Product.match` each line, a person confirms app/models/product.rb:166
- [ ] TODO search a country first: a bar in Brazil sees Brazil's Brahma app/models/product.rb:137
- [ ] TODO typo tolerance ("heiniken"): search is prefix only app/models/product.rb:137
- [ ] TODO es locale for Latin America config/locales/
- [ ] TODO lookup as a public API: ETag, Cache-Control, CORS app/controllers/products_controller.rb:16
- [ ] TODO admin filters: source, kind, country, no image app/views/products/index.html.erb
- [ ] TODO system specs (Capybara, Cuprite) for the form and the brand datalist spec/system/

## Engineering

- [ ] TODO importer finds row by row: bulk writes before the catalogue is millions lib/openmarket/importer.rb:48
- [ ] TODO RuboCop in CI .github/workflows/specs.yml
