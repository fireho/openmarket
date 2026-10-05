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

    org: nil    the shared catalogue — an admin curates it, every org selects it
    org: <Org>  that org's own: a recipe ("Caipirinha da Casa"), theirs alone

```ruby
Product.shared     # everybody's
Product.of(org)    # only that org's
Product.for(org)   # what that org may offer: shared + its own
```

`Product.for(nil)` is the shared catalogue, so a picker can always call it.
The host decides who may write which — typically supercow for the shared
ones, an org's own people for theirs.

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
folded words in `tokens` (refreshed on save), so every clause is a prefix on
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

The import and restore tasks first bring an existing database up to date:
they unset stored null codes, give old brands their folded `key` (warning
about two spellings of one name, to merge by hand), drop the old index that
made a code unique across orgs, create the indexes, and fill `tokens`.

**Load it** from the published dump — no scraping needed:

    bin/rails openmarket:restore                    # the latest GitHub release
    bin/rails openmarket:restore FILE=openmarket.ndjson.gz OVERWRITE=1

**Publish it** (`bin/rails openmarket:dump`, then attach `tmp/openmarket.ndjson.gz`
to a GitHub release). The dump is NDJSON — readable without Mongo:

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

## Installation

Rubygems already has an SMS gem named `openmarket`. Ours is git:

```ruby
gem "openmarket", git: "git@github.com:fireho/openmarket.git", branch: "main"
```

Needs mongoid and, for the enums, fire's `Enumere`. Locally: `bundle config set --local local.openmarket ../../git/openmarket`.

## Specs

`bin/rspec spec/lib` runs the plain-Ruby specs — barcodes, the Open Food Facts
mapper, the dump format, the importer on fake models — with no Rails and no Mongo.

The model and request specs (`spec/models`, `spec/requests`) need Mongo and the
fabricators here (`spec/fabricators/product_fabricator.rb`): one `:product`, with
`:drink` and `:food` inheriting it. The gem has no harness for those yet — the
host app that loads it runs them.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
