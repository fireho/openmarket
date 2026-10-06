# Openmarket

What a thing IS, never what it costs. One mongo collection of products —
name, code (ean/isbn), brand, image — with `Drink` and `Food` as the two
shapes that carry extra fields. The price lives in the host app, on whatever
offers the thing (a menu, a shelf, an order).

    Brand     Ambev, Coca-Cola — a name products point at (+ wikidata, country, site, logo)
    Product   the thing: name, code, sku, brand, org (+ image, quantity, countries, tags, source)
    Drink     + kind (beer, gin, wine...), pack (can, grf, pet...), size ml, acl % (a float, nil when unknown)
    Food      + kind (pizza, burger, meat...), size g

The goal is an open catalogue of the world's drinks (food after) that anyone
can load: a bar scans a Brahma and never types it. See *The open catalogue* below.

`Drink` and `Food` are STI on the `products` collection, so one query reads
the whole catalogue and `product.drink?` asks what a row is.

## Who owns a product

    org_id: nil   the shared catalogue — an admin curates it, every org selects it
    org_id: <id>  that owner's own: a recipe ("Caipirinha da Casa"), theirs alone

```ruby
Product.shared     # everybody's
Product.of(org)    # only that org's
Product.for(org)   # what that org may offer: shared + its own
```

`Product.for(nil)` is the shared catalogue, so a picker can always call it.
An owner is an id, not an association: the engine names no `Org` class, so
whatever owns things in your app (an org, a shop, a user) does. An app with an
`Org` model may add `Product.belongs_to :org` itself.

### Your app decides

The engine knows nothing of who asks. As it ships, its controllers show and
write the shared catalogue to whoever your `ApplicationController` lets in.
Anything else is yours to override:

```
  what                        override                             ships as
  who may come in             before_action                        whoever ApplicationController lets in
  which products              ProductsController#products          Product.shared
  a brand's page lists        BrandsController#products            Product.shared
  what a product form writes  ProductsController#product_params    the form's fields, never org_id
  a page                      app/views/products/*, brands/*       the engine's
  why a save was refused      app/views/openmarket/_errors         the engine's
```

Subclass, and draw the product routes to yours; `super` is the engine's.
An org's shelf, say — the catalogue and its own to look at, only its own to
write:

```ruby
class Bar::ProductsController < ProductsController
  prepend_before_action :authenticate_user! # before the engine's set_product reads `products`

  private

  def products = action_name.in?(%w[ edit update destroy ]) ? Product.of(current_org) : Product.for(current_org)
  def product_params = super.merge(org_id: current_org.id)
end
```

```ruby
resources :products, controller: "bar/products" do
  collection do
    get :search
    get "lookup/:code", action: :lookup, as: :lookup
  end
end
```

The engine's pages link with `products_path` and friends, so one controller
answers to those names. A scan through `products` finds an org's own before
the shared one with the same barcode. The specs run this very subclass
(`spec/dummy/app/controllers/bar_products_controller.rb`), at /bar/products
beside the engine's own, over JSON. For what needs no
`super` — a `before_action`, `products` — reopening the engine's controller
with `class_eval` in a `config.to_prepare` block works too.

## Kinds and packs

`kind` and `pack` are [Enumere](../fire) enums: symbols when you write them,
strings when you read them back, so the model validates its own list.

```ruby
Drink.kinds.keys            # => ["beer", "water", "whisky", ...]
drink = Drink.new(kind: :beer, pack: :can, size: 350, acl: "7.6%")
drink.kind                  # => "beer"
drink.acl                   # => 7.6  (a float, however it was written: "7,6", 7.6, "7.6%")
drink.alcohol               # => "7.6%"
drink.kind_name             # => "Cerveja" (i18n, mongoid.attributes.drink.kind_enums)
```

## Search

```ruby
Product.search("antar orig")   # => Cerveja Antártica Original
```

What someone typing wants: every word the start of a word in the product's
names (any language) or its brand's, with accents and case folded away — or
the start of a code, or the start of a brand's name. Each product keeps those
folded words in `tokens` (refreshed on save, and for all of a brand's
products when the brand is renamed), so every clause is a prefix on
an index and stays fast on a big catalogue. The term is text, never a regexp.

A product's `name` falls back to any language it has: a row imported as
`{ "es" => "Cerveza Quilmes" }` still reads "Cerveza Quilmes" in pt.

## Lookup

```ruby
Product.lookup("7 891991 010023")   # => the product, or nil
```

A barcode in any spelling finds the one product it names. `Openmarket::Ean`
files every GTIN by its value, as Open Food Facts does: a UPC-A gets its
leading zero (EAN-13), an EAN-8 stays 8 digits however it is padded, a GTIN-14
with a zero indicator is the EAN-13 inside it, and a UPC-E (the short code on
a 12oz can) is expanded to its UPC-A. Check digits are checked; a code that is
not a barcode (a house code) is kept as typed. A code is unique per owner: the
shared catalogue has one Brahma, and an org may file its own under the same
barcode (`lookup(code, org:)` gives the org's own first). Over HTTP:

    GET /products/lookup/7891991010023.json    one product, 404 if the catalogue lacks it
    GET /products/search.json?q=brah           up to 20, name, code or brand

## Brands

```ruby
Brand.search("antar")          # => Antártica — the start of a name, accents and case aside, in name order
product.brand_name = "brahma"  # finds Brahma however it is typed, makes it when new; "" takes the brand off
```

A brand is found by its folded `key`, so "Antártica" and "ANTARTICA " are one
brand (a BOM or zero-width space pasted at either end is ignored too), and a
list in name order puts "ambev" among the A's. A brand that still has products
is not destroyed: move its products first. Blank fields are stored as nothing.

There is a light admin at /brands (list, search, show with its products, edit),
and the product form takes the brand as a name, suggesting names from the
catalogue while you type. Over HTTP:

    GET /brands.json?search=amb        brands in name order, 50 a page
    GET /brands/:id.json               a brand, products_count, its products as links (50 a page, `next`)
    GET /brands/search.json?q=amb      up to 20, for a typeahead
    POST/PATCH/DELETE /brands[/:id]    as for products; DELETE is 422 while the brand has products

## Reading a menu

A bar pastes its menu or a distributor's price list instead of typing each item:

```ruby
Openmarket::Line.parse("Cerveja Patagonia LATA 350ml  R$ 12,90")
# => { type: "Drink", name: "Cerveja Patagonia", kind: :beer, pack: :can, size: 350, acl: nil, code: nil }
Openmarket::Line.parse_all(File.read("menu.txt"))  # one hash per product line, with :line, :text and :error

Product.parse("Heineken LN 330")      # => an unsaved Drink: 330 ml, a bottle
Product.match("Brahma 600ml", org:)   # => the catalogue's Brahma 600 ml, if it has one
```

It reads pt, es and en: the kind from keywords, the pack (lata, garrafa/LN,
PET, kit, "6x350ml"), the size (ml for a drink, cc included; g for food), the
ABV only when written, and a barcode only when it passes its check digit. The
price is dropped. Whatever the line does not say stays nil and is never
guessed: "Heineken LN 330" is a 330 ml bottle of no kind, "Café 500g" has no
type. Between a drink and a dish, the word a small word ties to the other is
the ingredient: "Picanha ao molho de vinho" is meat, "Batida de amendoim" a
drink. In `parse_all`, a heading ("Cervejas:", "== Drinks ==") gives its kind
to the lines under it that name none.

## The open catalogue

The shared catalogue (`org: nil`) is meant to be public: filled from open
sources, published as one file, loadable anywhere.

**Fill it** from Open Food Facts — drinks only, and only those it can place
(kind, valid barcode, a name); a row it cannot place is skipped, never guessed.

    bin/rails openmarket:import:off FILE=openfoodfacts-products.jsonl.gz COUNTRIES=en:brazil
    bin/rails openmarket:import:off LIMIT=1000      # no FILE: downloads their dump (several GB)

Re-running refreshes what an import wrote and leaves alone what a person
corrected: `source` is `"off"` on imported rows, and any edit by a person to
what a row says (name, code, kind, size...) clears it, so the row is theirs.

**Brands from Wikidata.** What Wikidata knows about a brand fills in what the
brand lacks: its id (QID), the country it is from, its official site, its logo.

    bin/rails openmarket:import:wikidata                 # every brand without a wikidata id
    bin/rails openmarket:import:wikidata LIMIT=500       # then AFTER=<the name it printed>

A name meets an item only by an exact label (en, pt, es, fr, de, it), and only
an item that is a brand. A name two items answer to is left out: a wrong QID
in an open catalogue spreads, a missing one is only missing. Only blank fields
are written, so a site or a logo a person set stays theirs. Brands go in name
order, 100 to a query, a second apart; a query Wikidata fails on is reported
and passed over, and being throttled stops the run with the AFTER= to go on
from.

The import and restore tasks first bring an existing database up to date:
they unset stored null codes, give old brands their folded `key` (warning
about two spellings of one name, to merge by hand), drop the old index that
made a code unique across orgs, create the indexes, and fill `tokens`.

**Load it** from the published dump — no scraping needed:

    bin/rails openmarket:restore                    # the latest GitHub release, else the gem's snapshot
    bin/rails openmarket:restore FILE=openmarket.ndjson.gz OVERWRITE=1

**The snapshot.** The gem ships one: `db/openmarket.ndjson.gz` (4.5MB,
`Openmarket::SNAPSHOT`), built with `bin/build-dump` from the Open Food Facts
export of 2026-10-05. 108,174 drinks and 21,457 brands, sold in 220 countries
and territories (France, the US and Germany lead):

    juice 26,341   soda 19,973   water 16,229   wine 15,952   beer 12,724
    energy 5,122   tea 4,971     liquor 2,207   cider 1,381   mixed 753
    whisky 670     rum 652       vodka 527      gin 388       cognac 174
    tequila 91     cachaça 19

88% have a picture, 78% a brand, 69% an ABV, 54% a size. Brazil is thin in
Open Food Facts (433 drinks: Brahma, Skol, Guaraná Antarctica, 51...), so a bar
there will still add its own — and every product scanned and corrected is one
more for the next release. Monthly releases replace the snapshot; it is
refreshed in the gem now and then, not every month.

**Publish it.** A GitHub Action (`.github/workflows/dump.yml`) rebuilds the dump
from Open Food Facts on the 2nd of every month — no Mongo, no Rails — and
publishes it as a release (`data-YYYY-MM-DD`, marked latest), which is what
`openmarket:restore` downloads. Run it by hand from the Actions tab too; a run
limited to some countries or to N drinks is a prerelease, never the latest.
Locally:

    curl -fsSL https://static.openfoodfacts.org/data/openfoodfacts-products.jsonl.gz \
      | bin/build-dump --off - --wikidata --out openmarket.ndjson.gz
    bin/build-dump --off openfoodfacts-products.jsonl.gz --countries en:brazil --limit 1000

`bin/build-dump` needs only Ruby's standard library and streams the ~13GB
export without storing it. (static.openfoodfacts.org redirects to their S3
bucket, `https://openfoodfacts-ds.s3.eu-west-3.amazonaws.com/openfoodfacts-products.jsonl.gz`,
which also works where the first host is blocked.) Two rows with one barcode
(a UPC-E and its UPC-A) become one product, and the row that says more is kept.
A brand is named the way most of its products spell it. `--wikidata` fills in
brands from Wikidata; if that fails it warns and builds anyway. `bin/rails
openmarket:dump` still writes a host's own shared catalogue.

The dump is NDJSON — readable without Mongo:

    zcat openmarket.ndjson.gz | jq -c 'select(.code == "7891991010023")'

    {"openmarket":1,"generated_at":"2026-10-05","license":"ODbL-1.0",...}
    {"type":"brand","name":"Brahma"}
    {"type":"drink","code":"7891991010023","name":{"pt":"Cerveja Brahma"},"brand":"Brahma","kind":"beer","pack":"can","size":350,"acl":4.8,...}

Records are keyed by code and brand name, never by a Mongo id, and sorted, so a
dump loads into any database and two dumps diff cleanly. Only shared products
with a code travel: an org's own products, `sku` and `uses` never leave.

### Data and license

The code is MIT. The data is not: what comes from [Open Food Facts](https://world.openfoodfacts.org)
is under the [ODbL 1.0](https://opendatacommons.org/licenses/odbl/1-0/), so a
dump built from it is published under the ODbL too, with attribution (the dump's
header carries the notice). Product images are not copied — `image` is a link to
where they live, under their own license.

Brand facts from [Wikidata](https://www.wikidata.org) (QID, country, site) are
CC0, so they travel in the dump as they are. A `logo` is a link to its file on
Wikimedia Commons, under that file's own license, never a copy.

## Installation

Rubygems already has an SMS gem named `openmarket`. Ours is git:

```ruby
gem "openmarket", git: "git@github.com:fireho/openmarket.git", branch: "main"
```

Needs mongoid and, for the enums, fire's `Enumere`. Locally: `bundle config set --local local.openmarket ../../git/openmarket`.

## Specs

`bin/rspec spec/lib` runs the plain-Ruby specs — barcodes, the Open Food Facts
mapper, the dump format and its builder, the importer on fake models, the menu
reader, the Wikidata client on a made-up answer — with no Rails and no Mongo.
GitHub Actions runs them on every push and pull request (`.github/workflows/specs.yml`).

The model, request and routing specs boot `spec/dummy`, the smallest host the
engine runs in, on a real Mongo:

```
  spec/lib       plain Ruby          bin/rspec spec/lib
  spec/models    ┐
  spec/requests  ├─ spec/dummy + Mongo   MONGO_TEST_DB=openmarket_<who> bin/rspec spec/models spec/requests spec/routing
  spec/routing   ┘
```

The dummy plays the host's part: an `Org`, pagy, a currency for Money, the
catalogue routes drawn at its top level, and one override
(`BarProductsController`, see Your app decides). Until Enumere is published,
`spec/dummy/app/models/concerns/enumere.rb` stands in for it — the part
openmarket reads, same contract (a String field, members keyed by string). A
host that has the real one never loads it.

Every run drops the test database and rebuilds its indexes from the models;
`MONGO_HOST` points it elsewhere than `localhost:27017`. CI runs both halves,
the second against a `mongo:7` service. The fabricators
(`spec/fabricators/product_fabricator.rb`) are one `:product`, with `:drink`
and `:food` inheriting it.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
