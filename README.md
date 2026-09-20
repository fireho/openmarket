# Openmarket

What a thing IS, never what it costs. One mongo collection of products —
name, code (ean/isbn), brand, image — with `Drink` and `Food` as the two
shapes that carry extra fields. The price lives in the host app, on whatever
offers the thing (a menu, a shelf, an order).

    Brand     Ambev, Coca-Cola — a name products point at
    Product   the thing: name, code, sku, brand, org
    Drink     + kind (beer, gin, wine...), pack (can, grf, pet...), size ml, acl %
    Food      + kind (pizza, burger, meat...), size g

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
drink.acl                   # => 8  (rounded percent, however it was written)
drink.kind_name             # => "Cerveja" (i18n, mongoid.attributes.drink.kind_enums)
```

## Search

```ruby
Product.search("brahma")    # name, code, or the brand's name
```

Name is localized, so mongoid queries the current locale. Brand is a
relation: search looks brands up by name and matches `brand_id`.

## Installation

Rubygems already has an SMS gem named `openmarket`. Ours is git:

```ruby
gem "openmarket", git: "git@github.com:fireho/openmarket.git", branch: "main"
```

Needs mongoid and, for the enums, fire's `Enumere`. Locally: `bundle config set --local local.openmarket ../../git/openmarket`.

## Specs

The fabricators are here (`spec/fabricators/product_fabricator.rb`): one
`:product`, with `:drink` and `:food` inheriting it. The gem has no harness of
its own yet — the host app that loads it runs them.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
