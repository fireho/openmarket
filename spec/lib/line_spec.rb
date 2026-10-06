require "standalone_helper"
require "stringio"
require "openmarket/line"

RSpec.describe Openmarket::Line do
  # Every field: one the line does not say must come back nil, not guessed.
  let(:nothing) { { type: nil, name: nil, kind: nil, pack: nil, size: nil, acl: nil, code: nil } }

  def self.reads(table)
    table.each do |line, said|
      it "reads #{line.inspect}" do
        expect(described_class.parse(line)).to eq(nothing.merge(said))
      end
    end
  end

  def parse(line) = described_class.parse(line)

  describe ".parse" do
    context "the lines the old Drink.import and Food.import were written for" do
      reads(
        "Cerveja Patagonia LATA 350ml"      => { type: "Drink", name: "Cerveja Patagonia", kind: :beer, pack: :can, size: 350 },
        "Cerveja Patagonia Lata 269 ml"     => { type: "Drink", name: "Cerveja Patagonia", kind: :beer, pack: :can, size: 269 },
        "Cerveja Amstel - GRF 330ml"        => { type: "Drink", name: "Cerveja Amstel", kind: :beer, pack: :grf, size: 330 },
        "Cerveja Amstel GRF 550 ml"         => { type: "Drink", name: "Cerveja Amstel", kind: :beer, pack: :grf, size: 550 },
        "Energético Furioso PET 2000 ml"    => { type: "Drink", name: "Energético Furioso", kind: :energy, pack: :pet, size: 2000 },
        "Refrigerante Furioso-Pet 200ml"    => { type: "Drink", name: "Refrigerante Furioso", kind: :soda, pack: :pet, size: 200 },
        "Chocolate Montanha PC 500g"        => { type: "Food", name: "Chocolate Montanha", kind: :dessert, size: 500 },
        "Antipasto de Azeitona - Lata 230g" => { type: "Food", name: "Antipasto de Azeitona", kind: :snack, size: 230 }
      )
    end

    context "a Brazilian bar's list" do
      reads(
        "Cerveja Brahma 600ml R$ 12,90"             => { type: "Drink", name: "Cerveja Brahma", kind: :beer, size: 600 },
        "Chopp Brahma 300ml R$ 9,90"                => { type: "Drink", name: "Chopp Brahma", kind: :beer, size: 300 },
        "Cerveja Skol Pilsen 6x350ml"               => { type: "Drink", name: "Cerveja Skol Pilsen", kind: :beer, pack: :kit, size: 350 },
        "Fardo Skol 12 latas 350ml"                 => { type: "Drink", name: "Skol", pack: :kit, size: 350 },
        "Heineken Long Neck 330ml R$ 12,00"         => { type: "Drink", name: "Heineken", pack: :grf, size: 330 },
        "Heineken LN 330"                           => { type: "Drink", name: "Heineken", pack: :grf, size: 330 },
        "Heineken 0,0% Long Neck 330ml"             => { type: "Drink", name: "Heineken", pack: :grf, size: 330, acl: 0.0 },
        "Água sem gás 500ml"                        => { type: "Drink", name: "Água sem gás", kind: :water, size: 500 },
        "Água Crystal 500ml com gás R$ 5,00"        => { type: "Drink", name: "Água Crystal com gás", kind: :water, size: 500 },
        "Água tônica Schweppes Lata 350ml"          => { type: "Drink", name: "Água tônica Schweppes", kind: :soda, pack: :can, size: 350 },
        "Coca-Cola Lata 350ml"                      => { type: "Drink", name: "Coca-Cola", kind: :soda, pack: :can, size: 350 },
        "Guaraná Antarctica 2L PET"                 => { type: "Drink", name: "Guaraná Antarctica", kind: :soda, pack: :pet, size: 2000 },
        "Suco de laranja natural 500ml"             => { type: "Drink", name: "Suco de laranja natural", kind: :juice, size: 500 },
        "Chá gelado de pêssego 450ml"               => { type: "Drink", name: "Chá gelado de pêssego", kind: :tea, size: 450 },
        "Red Bull Energy Drink 250ml"               => { type: "Drink", name: "Red Bull Energy Drink", kind: :energy, size: 250 },
        "Vinho Tinto Casillero del Diablo 750ml"    => { type: "Drink", name: "Vinho Tinto Casillero del Diablo", kind: :wine, size: 750 },
        "Espumante Chandon Brut 750ml"              => { type: "Drink", name: "Espumante Chandon Brut", kind: :wine, size: 750 },
        "Dose de Cachaça 50ml"                      => { type: "Drink", name: "Dose de Cachaça", kind: :cachaca, size: 50 },
        "Cachaça 51 Garrafa 965ml"                  => { type: "Drink", name: "Cachaça 51", kind: :cachaca, pack: :grf, size: 965 },
        "Whisky Johnnie Walker Red Label dose 50ml" => { type: "Drink", name: "Whisky Johnnie Walker Red Label dose", kind: :whisky, size: 50 },
        "Smirnoff Ice 275ml"                        => { type: "Drink", name: "Smirnoff Ice", kind: :mixed, size: 275 },
        "Caipirinha de limão ........ R$ 22,00"     => { type: "Drink", name: "Caipirinha de limão", kind: :mixed },
        "Porção de batata frita 400g"               => { type: "Food", name: "Porção de batata frita", kind: :snack, size: 400 },
        "Amendoim japonês 150g"                     => { type: "Food", name: "Amendoim japonês", kind: :snack, size: 150 },
        "Picanha na chapa 500g R$ 89,90"            => { type: "Food", name: "Picanha na chapa", kind: :meat, size: 500 },
        "Picanha 500g com arroz e farofa"           => { type: "Food", name: "Picanha com arroz e farofa", kind: :meat, size: 500 },
        "Costelinha na cerveja 500g R$ 49,90"       => { type: "Food", name: "Costelinha na cerveja", kind: :meat, size: 500 },
        "Isca de peixe na cerveja 400g"             => { type: "Food", name: "Isca de peixe na cerveja", kind: :snack, size: 400 },
        "Hambúrguer artesanal 180g"                 => { type: "Food", name: "Hambúrguer artesanal", kind: :burger, size: 180 },
        "X-Salada R$ 18,00"                         => { type: "Food", name: "X-Salada", kind: :burger },
        "Pizza Calabresa grande R$ 59,90"           => { type: "Food", name: "Pizza Calabresa grande", kind: :pizza },
        "Temaki de salmão R$ 29,90"                 => { type: "Food", name: "Temaki de salmão", kind: :sushi },
        "Petit gâteau com sorvete R$ 24,90"         => { type: "Food", name: "Petit gâteau com sorvete", kind: :dessert }
      )
    end

    context "an Argentinian one" do
      reads(
        "Cerveza Quilmes Clásica 1 L $ 1.500" => { type: "Drink", name: "Cerveza Quilmes Clásica", kind: :beer, size: 1000 },
        "Fernet Branca 750 ml $ 9.500"        => { type: "Drink", name: "Fernet Branca", kind: :liquor, size: 750 },
        "Fernet Branca 750cc $ 9.500"         => { type: "Drink", name: "Fernet Branca", kind: :liquor, size: 750 },
        "Cerveza Andes Origen Rubia 473cc"    => { type: "Drink", name: "Cerveza Andes Origen Rubia", kind: :beer, size: 473 },
        "Quilmes Cristal 970 cc"              => { type: "Drink", name: "Quilmes Cristal", size: 970 },
        "Fernet con Coca $ 3.000"             => { type: "Drink", name: "Fernet con Coca", kind: :mixed },
        "Vino Malbec Trapiche 750ml $ 6.200"  => { type: "Drink", name: "Vino Malbec Trapiche", kind: :wine, size: 750 },
        "Agua sin gas Villavicencio 500 ml"   => { type: "Drink", name: "Agua sin gas Villavicencio", kind: :water, size: 500 },
        "Gaseosa Coca-Cola 1,5 L"             => { type: "Drink", name: "Gaseosa Coca-Cola", kind: :soda, size: 1500 },
        "Bife de chorizo 400g $ 18.500"       => { type: "Food", name: "Bife de chorizo", kind: :meat, size: 400 },
        "Bife de chorizo 400g con papas fritas" => { type: "Food", name: "Bife de chorizo con papas fritas", kind: :meat, size: 400 },
        "Picada para 2 $ 12.000"              => { type: "Food", name: "Picada para 2", kind: :snack }
      )
    end

    context "a US one, in ounces: fluid on a drink, weight on food" do
      reads(
        "Bud Light Lager 12oz can $5.50"         => { type: "Drink", name: "Bud Light Lager", kind: :beer, pack: :can, size: 355 },
        "Sierra Nevada Pale Ale 12 oz bottle $7" => { type: "Drink", name: "Sierra Nevada Pale Ale", kind: :beer, pack: :grf, size: 355 },
        "Coca-Cola 20 oz bottle $2.49"           => { type: "Drink", name: "Coca-Cola", kind: :soda, pack: :grf, size: 591 },
        "Jameson Irish Whiskey 1.5 oz $9"        => { type: "Drink", name: "Jameson Irish Whiskey", kind: :whisky, size: 44 },
        "Tito's Handmade Vodka 1L 40% ABV $30"   => { type: "Drink", name: "Tito's Handmade Vodka", kind: :vodka, size: 1000, acl: 40.0 },
        "Classic Cheeseburger 8oz $14"           => { type: "Food", name: "Classic Cheeseburger", kind: :burger, size: 227 },
        "Ribeye Steak 12 oz $32"                 => { type: "Food", name: "Ribeye Steak", kind: :meat, size: 340 },
        "Ribeye 12oz with fries $32"             => { type: "Food", name: "Ribeye with fries", kind: :meat, size: 340 }
      )
    end

    describe "prices" do
      it "drops them, and never reads one as a size" do
        expect(parse("Heineken LN R$ 12,90")).to include(name: "Heineken", size: nil)
        expect(parse("Heineken LN 12,90")).to include(name: "Heineken", size: nil)
        expect(parse("Quilmes 1 L 1.500")).to include(name: "Quilmes", size: 1000)
      end

      it "takes a number in a column of its own as the price" do
        expect(parse("Caipirinha\t25")).to include(name: "Caipirinha", size: nil)
        expect(parse("Porção de calabresa | 35")).to include(name: "Porção de calabresa", size: nil)
        expect(parse("Heineken LN 330ml ..... 12")).to include(name: "Heineken", size: 330)
      end

      it "leaves a plain number in the name: it may be anything" do
        expect(parse("Licor 43 700ml")).to include(name: "Licor 43", size: 700)
        expect(parse("Heineken 600ml 15")).to include(name: "Heineken 15", size: 600)
      end
    end

    describe "sizes" do
      it "is the size of one in a kit" do
        expect(parse("Skol 269ml x 12")).to include(pack: :kit, size: 269)
        expect(parse("Heineken LN 330ml c/ 6")).to include(name: "Heineken", pack: :kit, size: 330)
        expect(parse("Kit 6 Heineken LN 330ml")).to include(name: "Heineken", pack: :kit, size: 330)
        expect(parse("Brahma 350ml cx 12")).to include(name: "Brahma", pack: :kit, size: 350)
      end

      it "counts only with a plural or an x" do
        expect(parse("Cachaça 51 Garrafa 965ml")).to include(pack: :grf, size: 965)
        expect(parse("Pack 12 un 350ml Brahma")).to include(name: "Brahma", pack: :kit, size: 350)
      end

      it "reads litres, kilos and thousands" do
        expect(parse("Vinho 1,5 L")[:size]).to eq(1500)
        expect(parse("Costela 1,2 kg")[:size]).to eq(1200)
        expect(parse("Picanha 1.000 g")[:size]).to eq(1000)
        expect(parse("Coca-Cola 2L (2000ml)")).to include(name: "Coca-Cola", size: 2000)
      end

      it "is none when the unit is not the type's: food is weighed, drinks are measured" do
        expect(parse("Sorvete de creme 1,5 L")).to include(type: "Food", kind: :dessert, size: nil)
        expect(parse("Chocolate quente 300ml")).to include(type: "Drink", kind: nil, size: 300)
      end

      it "reads cc, as Argentina writes millilitres" do
        expect(parse("Quilmes 1000cc")).to eq(nothing.merge(type: "Drink", name: "Quilmes", size: 1000))
        expect(parse("Vino tinto Malbec 750 cc")).to include(name: "Vino tinto Malbec", kind: :wine, size: 750)
        expect(parse("Cerveza 6 x 473cc")).to include(name: "Cerveza", pack: :kit, size: 473)
        expect(parse("Agua 500 cm³")).to include(name: "Agua", size: 500)
      end

      it "is none without a type to give a bare number its unit" do
        expect(parse("Brahma Lata 350")).to eq(nothing.merge(name: "Brahma", pack: :can))
      end
    end

    describe "ABV" do
      it "reads it said outright, before or after the number" do
        expect(parse("Tequila José Cuervo Especial 750ml 38% vol")).to include(name: "Tequila José Cuervo Especial", acl: 38.0)
        expect(parse("Alc. 4,5% Cerveja Bohemia 350ml")).to include(name: "Cerveja Bohemia", acl: 4.5)
        expect(parse("Cerveja 4,8 % vol. 350ml")).to include(name: "Cerveja", acl: 4.8)
      end

      it "reads a bare percent on a drink" do
        expect(parse("Cerveja IPA Colorado 600ml 7%")).to include(name: "Cerveja IPA Colorado", acl: 7.0)
      end

      it "takes no percent that is not alcohol" do
        expect(parse("Suco de Uva Integral 100% 1L")).to include(name: "Suco de Uva Integral 100%", acl: nil)
        expect(parse("Suco 50% fruta 1L")).to include(name: "Suco 50% fruta", acl: nil)
        expect(parse("Chocolate 70% cacau 100g")).to include(type: "Food", name: "Chocolate 70% cacau", acl: nil)
      end

      it "never takes it from the kind: a beer with no label data is not a 5% beer" do
        expect(parse("Cerveja Brahma 600ml")[:acl]).to be_nil
      end
    end

    describe "kinds" do
      it "lets a longer word win over one inside it" do
        expect(parse("Água tônica")[:kind]).to eq(:soda)
        expect(parse("Gin Tônica Tanqueray")[:kind]).to eq(:mixed)
        expect(parse("Ice tea limão 300ml")[:kind]).to eq(:tea)
        expect(parse("Ginger beer 350ml")[:kind]).to eq(:soda)
      end

      it "puts a cocktail before its spirit, a liqueur before its whisky, a beer before its tequila" do
        expect(parse("Caipiroska de morango")[:kind]).to eq(:mixed)
        expect(parse("Batida de amendoim")).to include(type: "Drink", kind: :mixed)
        expect(parse("Licor de chocolate 700ml")).to include(type: "Drink", kind: :liquor)
        expect(parse("Desperados Tequila Beer 330ml")[:kind]).to eq(:beer)
      end

      it "puts a dish before what is in it, and otherwise the first word" do
        expect(parse("Hambúrguer de picanha 180g")[:kind]).to eq(:burger)
        expect(parse("Picanha com fritas 500g")[:kind]).to eq(:meat)
        expect(parse("Porção de picanha 400g")[:kind]).to eq(:snack)
        expect(parse("Pudim de café")).to include(type: "Food", kind: :dessert)
      end

      it "takes, between a drink and a dish, the one no small word ties to the other" do
        expect(parse("Picanha ao molho de vinho")).to include(type: "Food", kind: :meat)
        expect(parse("Bombom de licor")).to include(type: "Food", kind: :dessert)
        expect(parse("Café com chocolate")).to include(type: "Drink", kind: nil)
        expect(parse("Milkshake de chocolate 400ml")).to include(type: "Drink", kind: nil, size: 400)
        expect(parse("Chocolate Stout")).to include(type: "Drink", kind: :beer) # untied, a drink comes first
      end

      it "reads a drink a dish was cooked in as that dish" do
        expect(parse("Pera ao vinho")).to eq(nothing.merge(type: "Food", name: "Pera ao vinho"))
        expect(parse("Pollo a la cerveza")).to include(type: "Food", kind: nil)
        expect(parse("Mexilhões ao vinho branco 400g")).to include(type: "Food", kind: nil, size: 400)
        expect(parse("Cerveja no balde")).to include(type: "Drink", kind: :beer)
      end

      it "takes a weight to mean food, and never weighs a drink" do
        expect(parse("Rum cake 500g")).to include(type: "Food", kind: :dessert, size: 500)
        expect(parse("Bourbon glazed ribs 400g")).to include(type: "Food", kind: :meat, size: 400)
        expect(parse("Picanha ao molho de vinho 500g")).to include(type: "Food", kind: :meat, size: 500)
        expect(parse("Cerveja 500g")).to eq(nothing.merge(name: "Cerveja"))
      end

      it "knows a drink none of the kinds fit" do
        expect(parse("Café expresso")).to include(type: "Drink", kind: nil)
        expect(parse("Água de coco 300ml")).to include(type: "Drink", kind: nil, size: 300)
      end

      it "guesses nothing a line does not name" do
        expect(parse("Brahma Duplo Malte Lata 350ml")).to include(type: "Drink", kind: nil, pack: :can, size: 350)
        expect(parse("Café 3 Corações 500g")).to include(type: nil, kind: nil, size: nil) # beans, or a drink?
        expect(parse("Pão de queijo")).to eq(nothing.merge(name: "Pão de queijo"))
      end
    end

    describe "packs" do
      it "takes no 'can' that starts a name, nor a pet-nat" do
        expect(parse("Can Blau 750ml")).to include(name: "Can Blau", pack: nil)
        expect(parse("Pet-Nat Rosé 750ml")).to include(name: "Pet-Nat Rosé", pack: nil)
      end

      it "has none on food" do
        expect(parse("Antipasto de Azeitona - Lata 230g")[:pack]).to be_nil
      end
    end

    describe "names" do
      it "drops the separators and small words that hung on what was read" do
        expect(parse("Lata de Coca-Cola 350ml")[:name]).to eq("Coca-Cola")
        expect(parse("Coca-Cola garrafa de 2L")[:name]).to eq("Coca-Cola")
        expect(parse("Cerveja Brahma (lata 350ml)")[:name]).to eq("Cerveja Brahma")
        expect(parse("Heineken - LN - Puro Malte 330ml")[:name]).to eq("Heineken - Puro Malte")
      end

      it "keeps a small word that ties a cut to what follows, unless nothing comes before it" do
        expect(parse("Água 500ml com gás")[:name]).to eq("Água com gás")
        expect(parse("Picanha 500g com arroz")[:name]).to eq("Picanha com arroz")
        expect(parse("Pizza grande R$ 59,90 de calabresa")[:name]).to eq("Pizza grande de calabresa")
        expect(parse("Chopp 500ml em taça gelada")[:name]).to eq("Chopp em taça gelada")
        expect(parse("500ml de Coca-Cola")[:name]).to eq("Coca-Cola")
      end

      it "drops one just before a cut: it went with what was cut" do
        expect(parse("Cerveja de 600ml gelada")[:name]).to eq("Cerveja gelada")
        expect(parse("Coca-Cola de 2L com gelo")[:name]).to eq("Coca-Cola com gelo")
        expect(parse("Garrafa de 600ml de Original")[:name]).to eq("Original")
        expect(parse("Heineken na garrafa")[:name]).to eq("Heineken")
      end

      it "drops a list's bullet or number" do
        expect(parse("1. Heineken LN 330ml")[:name]).to eq("Heineken")
        expect(parse("- Brahma Duplo Malte Lata 350ml")[:name]).to eq("Brahma Duplo Malte")
      end

      it "keeps the accents of a list saved as Windows-1252" do
        latin = "Água sem gás 500ml".encode(Encoding::Windows_1252)

        expect(parse(latin.dup.force_encoding(Encoding::UTF_8))[:name]).to eq("Água sem gás")
        expect(parse(latin.dup.force_encoding(Encoding::BINARY))[:name]).to eq("Água sem gás")
        expect(parse(latin)[:name]).to eq("Água sem gás")
      end

      it "is nil when nothing is left" do
        expect(parse("Long Neck 355ml")).to eq(nothing.merge(type: "Drink", pack: :grf, size: 355))
        expect(parse("R$ 12,90")).to eq(nothing)
        expect(parse(nil)).to eq(nothing)
      end
    end

    describe "barcodes" do
      it "reads one that passes its check digit" do
        expect(parse("EAN 7891991010023 Cerveja 350ml")).to include(name: "Cerveja", code: "7891991010023")
        expect(parse("036000291452 Refrigerante 12oz can")).to include(name: "Refrigerante", code: "0036000291452")
      end

      it "leaves a number that fails it alone" do
        expect(parse("7891991010024 Cerveja")).to include(name: "7891991010024 Cerveja", code: nil)
      end
    end
  end

  describe ".parse_all" do
    let(:menu) do
      <<~MENU
        # Bar do Zé
        Cervejas:
        Heineken LN 330ml ........ R$ 12,90
        Stella Artois Long Neck 275ml\tR$ 11,00

        == Drinks ==
        Limão R$ 22
        Smirnoff Ice 275ml
        Porções:
        Batata frita 400g R$ 32,00
        Xyz 2L
        R$ 10,00
        ----
        // fim
      MENU
    end

    subject(:found) { described_class.parse_all(menu) }

    it "makes one result per product line, numbered as pasted" do
      expect(found.map { |line| line[:line] }).to eq([ 3, 4, 7, 8, 10, 11, 12 ])
      expect(found.first).to eq(nothing.merge(line: 3, text: "Heineken LN 330ml ........ R$ 12,90",
                                              type: "Drink", name: "Heineken", kind: :beer, pack: :grf, size: 330))
    end

    it "gives a line that names no kind the kind of its heading" do
      expect(found[1]).to include(name: "Stella Artois", kind: :beer)
      expect(found[2]).to include(name: "Limão", type: "Drink", kind: :mixed)
      expect(found[4]).to include(name: "Batata frita", kind: :snack)
    end

    it "keeps a line's own kind, and its own type over the heading's" do
      expect(found[3]).to include(name: "Smirnoff Ice", kind: :mixed)
      expect(found[5]).to include(name: "Xyz", type: "Drink", kind: nil, size: 2000)
    end

    it "says which line named nothing, and gives it no kind" do
      expect(found.last).to eq(nothing.merge(line: 12, text: "R$ 10,00", error: "no name"))
      expect(found.first).not_to have_key(:error)
    end

    it "gives only the type of a heading that names two kinds, and nothing of one that names a drink and a dish" do
      found = described_class.parse_all("Águas e Refrigerantes:\nCrystal sem gás 500ml\nSucos e Refrigerantes:\nLaranja 300ml\n" \
                                        "Cervejas e Drinks:\nHeineken LN 330\nPetiscos e Cervejas:\nXyz\n")

      expect(found.map { |line| line.values_at(:name, :type, :kind) }).to eq([
        [ "Crystal sem gás", "Drink", nil ], [ "Laranja", "Drink", nil ], [ "Heineken", "Drink", nil ], [ "Xyz", nil, nil ]
      ])
    end

    it "reads a bare percent on a line only its heading makes a drink" do
      expect(described_class.parse("Patagonia Amber 5%")).to eq(nothing.merge(name: "Patagonia Amber 5%"))
      expect(described_class.parse_all("Cervejas:\nPatagonia Amber 5%")).to contain_exactly(
        include(type: "Drink", name: "Patagonia Amber", kind: :beer, acl: 5.0)
      )
    end

    it "reads an IO too" do
      expect(described_class.parse_all(StringIO.new("Coca-Cola Lata 350ml\n")))
        .to eq([ nothing.merge(line: 1, text: "Coca-Cola Lata 350ml", type: "Drink", name: "Coca-Cola", kind: :soda, pack: :can, size: 350) ])
    end

    it "reads a file Excel saved as UTF-8, mark and all" do
      expect(described_class.parse_all("﻿# from Excel\nHeineken LN 330ml\n").map { |line| line[:text] }).to eq([ "Heineken LN 330ml" ])
    end

    it "is empty for nothing" do
      expect(described_class.parse_all(nil)).to eq([])
      expect(described_class.parse_all("\n  \n# only a comment\n")).to eq([])
    end
  end

  describe "KIND_WORDS" do
    it "holds the words that only say the kind, folded" do
      expect(Openmarket::Line::KIND_WORDS).to include("cerveja", "refrigerante", "agua", "suco", "vinho")
      expect(Openmarket::Line::KIND_WORDS).not_to include("heineken", "brahma")
    end
  end
end
