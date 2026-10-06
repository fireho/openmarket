require "standalone_helper"
require "support/fake_models"
require "openmarket/builder"
require "open3"
require "rbconfig"
require "tmpdir"
require "yaml"

RSpec.describe Openmarket::Builder do
  let(:builder) { described_class.new }

  # An Open Food Facts row. `entry` is that row mapped: what the builder is fed.
  def row(code: "7891991010023", brands: "Brahma", **fields)
    {
      "code" => code, "lang" => "pt", "product_name" => "Cerveja Brahma", "brands" => brands, "quantity" => "350 ml",
      "categories_tags" => %w[ en:beverages en:alcoholic-beverages en:beers ], "packaging_tags" => %w[ en:can ],
      "countries_tags" => %w[ en:brazil ], "nutriments" => { "alcohol_100g" => 4.8 }
    }.merge(fields.transform_keys(&:to_s))
  end

  def entry(**fields) = Openmarket::OpenFoodFacts.map(row(**fields))

  def root = File.expand_path("../..", __dir__)

  def build(entries, **options)
    described_class.new(**options).tap { |built| entries.each { |one| built.add(one) } }
  end

  def brands_of(built) = built.records.select { |record| record["type"] == "brand" }
  def products_of(built) = built.records.reject { |record| record["type"] == "brand" }

  # Wikidata's answer for a brand. The ids are made up: no spec asks Wikidata.
  def wikidata(name, **fields)
    { "type" => "brand", "name" => name, "wikidata" => "Q-test", "country" => "BR", "source" => "wikidata" }.merge(fields.transform_keys(&:to_s))
  end

  describe "#add" do
    # 01234565 is a UPC-E; 012345000065 is the UPC-A it stands for.
    let(:twins) { [ entry(code: "01234565", packaging_tags: [], nutriments: {}), entry(code: "012345000065") ] }

    it "keeps one product for a UPC-E and its UPC-A, and counts the other" do
      built = build(twins)

      expect(products_of(built).map { |record| record["code"] }).to eq(%w[ 0012345000065 ])
      expect(built.stats).to include(read: 2, duplicates: 1, products: 1)
    end

    it "keeps the row that says more, whichever came first" do
      expect(products_of(build(twins))).to eq(products_of(build(twins.reverse)))
      expect(products_of(build(twins)).first).to include("pack" => "can", "acl" => 4.8)
    end

    it "picks the same one of two rows that say as much, whatever the order" do
      pair = [ entry(product_name: "Brahma Chopp"), entry(product_name: "Brahma Duplo Malte") ]

      expect(build(pair).records.to_a).to eq(build(pair.reverse).records.to_a)
    end

    it "says what it did with each entry" do
      expect(builder.add(entry)).to eq(:added)
      expect(builder.add(entry)).to eq(:duplicate)
      expect(builder.add({ code: " ", brand: nil, type: "Drink", attrs: {} })).to eq(:invalid)
      expect(builder.stats).to include(read: 3, duplicates: 1, invalid: 1, products: 1)
    end
  end

  describe "brands" do
    it "names a brand as most of its products spell it" do
      built = build([ entry(code: "7891991010023"), entry(code: "5901234123457", brands: "BRAHMA"),
                      entry(code: "4006381333931", brands: "Brahma "), entry(code: "96385074", brands: "brahma") ])

      expect(brands_of(built).map { |record| record["name"] }).to eq(%w[ Brahma ])
      expect(products_of(built).map { |record| record["brand"] }.uniq).to eq(%w[ Brahma ])
    end

    it "settles a tie alphabetically, whatever the order" do
      pair = [ entry(code: "7891991010023", brands: "Skol"), entry(code: "5901234123457", brands: "SKOL") ]

      expect(build(pair).brand_names).to eq(%w[ SKOL ])
      expect(build(pair.reverse).brand_names).to eq(%w[ SKOL ])
    end

    it "lists only the brands a product uses" do
      built = build([ entry(code: "01234565", brands: "Ambev", packaging_tags: [], nutriments: {}), entry(code: "012345000065") ])

      expect(brands_of(built).map { |record| record["name"] }).to eq(%w[ Brahma ])
    end

    it "takes a product with no brand" do
      built = build([ entry(brands: "") ])

      expect(brands_of(built)).to be_empty
      expect(products_of(built).first).not_to have_key("brand")
    end

    it "says a brand comes from Open Food Facts" do
      expect(brands_of(build([ entry ]))).to eq([ { "type" => "brand", "name" => "Brahma", "source" => "off" } ])
    end
  end

  describe "enrichment" do
    it "fills a brand in from Wikidata, matched however it is spelled" do
      built = build([ entry(brands: "ANTARTICA") ], brands: [ wikidata("Antártica", site: "https://example.com") ])

      expect(brands_of(built)).to eq([ {
        "type" => "brand", "name" => "ANTARTICA", "wikidata" => "Q-test", "country" => "BR",
        "site" => "https://example.com", "source" => "wikidata"
      } ])
      expect(built.stats).to include(brands: 1, wikidata: 1)
    end

    it "takes Wikidata records after the products are in" do
      built = build([ entry ])
      built.enrich([ wikidata("Brahma"), wikidata("Nobody's brand") ])

      expect(brands_of(built).map { |record| record["wikidata"] }).to eq([ "Q-test" ])
    end

    it "keeps the first record for a name" do
      built = build([ entry ], brands: [ wikidata("Brahma", country: "BR"), wikidata("BRAHMA", country: "PT") ])

      expect(brands_of(built).first["country"]).to eq("BR")
    end

    it "takes nothing from a fetch that breaks halfway" do
      broken = Enumerator.new do |out|
        out << wikidata("Brahma")
        raise SocketError, "wikidata.org unreachable"
      end
      built = build([ entry ])

      expect { built.enrich(broken) }.to raise_error(SocketError)
      expect(brands_of(built)).to eq([ { "type" => "brand", "name" => "Brahma", "source" => "off" } ])
    end
  end

  describe "#records" do
    it "gives brands by name, then products by code" do
      built = build([ entry(code: "7891991010023", brands: "Skol"), entry(code: "4006381333931", brands: "Brahma"),
                      entry(code: "5901234123457", brands: "Antarctica"), entry(code: "96385074", brands: "Brahma") ])

      expect(built.records.map { |record| record["name"].is_a?(String) ? record["name"] : record["code"] })
        .to eq(%w[ Antarctica Brahma Skol 4006381333931 5901234123457 7891991010023 96385074 ])
    end

    it "says a drink as Catalogue.product_record does, field for field and in order" do
      one = entry(product_name_en: "Brahma Beer", generic_name: "Cerveja pilsen",
                  image_front_url: "https://images.openfoodfacts.org/b.jpg")
      drink = Fake::Drink.new(one[:attrs].merge(brand: Fake::Brand.new(name: "Brahma")))
      expected = Openmarket::Dump.slim(Openmarket::Catalogue.product_record(drink, { drink.brand_id => "Brahma" }))

      expect(products_of(build([ one ])).first.to_a).to eq(expected.to_a)
    end

    it "says a brand as Catalogue.brand_record does" do
      record = wikidata("Brahma", info: "Brazilian beer", site: "https://example.com", logo: "https://example.com/logo.svg")
      brand = Fake::Brand.new(record.except("type").transform_keys(&:to_sym))
      expected = Openmarket::Dump.slim(Openmarket::Catalogue.brand_record(brand))

      expect(brands_of(build([ entry ], brands: [ record ])).first.to_a).to eq(expected.to_a)
    end
  end

  describe "a build, restored" do
    before { Fake.reset! }

    let(:built) do
      build([ entry(code: "7891991010023", product_name_en: "Brahma Beer"), entry(code: "5901234123457", brands: "brahma"),
              entry(code: "4006381333931", brands: "Antártica", product_name: "Guaraná", categories_tags: %w[ en:beverages en:sodas ], nutriments: {}),
              entry(code: "96385074", brands: nil) ],
            brands: [ wikidata("Antartica") ])
    end
    let(:path) { File.join(Dir.mktmpdir, "openmarket.ndjson.gz") }

    def restore = Openmarket::Catalogue.restore(path, brands: Fake::Brand, products: Fake::Product, types: Fake::TYPES)

    it "loads through Catalogue.entry and the importer" do
      expect(built.write(path)).to eq(6)
      expect(restore).to eq(created: 4)

      guarana = Fake::Product.rows.find { |product| product.code == "4006381333931" }
      expect(guarana).to be_a(Fake::Drink)
      expect(guarana).to have_attributes(kind: "soda", pack: "can", size: 350, acl: 0.0, source: "off")
      expect(guarana.brand).to have_attributes(name: "Antártica", wikidata: "Q-test", country: "BR", source: "wikidata")
      expect(Fake::Brand.rows.map(&:name)).to contain_exactly("Antártica", "Brahma")
    end

    it "dumps back to the same records" do
      built.write(path)
      restore

      names = Fake::Brand.rows.to_h { |brand| [ brand.object_id, brand.name ] }
      again = Fake::Brand.rows.sort_by(&:name).map { |brand| Openmarket::Catalogue.brand_record(brand) } +
              Fake::Product.rows.sort_by(&:code).map { |product| Openmarket::Catalogue.product_record(product, names) }

      expect(again.map { |record| Openmarket::Dump.slim(record).to_a }).to eq(built.records.map(&:to_a))
    end

    it "writes the same bytes for the same rows, in any order" do
      entries = [ entry(code: "7891991010023"), entry(code: "5901234123457", brands: "Skol") ]
      dir = Dir.mktmpdir
      build(entries).write(File.join(dir, "a.ndjson.gz"))
      build(entries.reverse).write(File.join(dir, "b.ndjson.gz"))

      expect(File.binread(File.join(dir, "a.ndjson.gz"))).to eq(File.binread(File.join(dir, "b.ndjson.gz")))
    end
  end

  describe "bin/build-dump" do
    let(:dir) { Dir.mktmpdir }
    let(:out) { File.join(dir, "out", "openmarket.ndjson.gz") }
    let(:export) do
      cola = row(code: "5901234123457", brands: "Cola Co", product_name: "Cola", lang: "en",
                 categories_tags: %w[ en:beverages en:sodas ], countries_tags: %w[ en:france ])
      food = { "code" => "4006381333931", "product_name" => "Granola", "categories_tags" => %w[ en:breakfasts ] }
      lines = [ row, row(code: "01234565", brands: "BRAHMA"), cola, food ].map(&:to_json) + [ "not json {en:beverages" ]
      Zlib.gzip(lines.join("\n") + "\n")
    end
    let(:path) { File.join(dir, "off.jsonl.gz").tap { |file| File.binwrite(file, export) } }

    # Without the bundle, as the GitHub Action runs it: Ruby's standard library only.
    def bin = File.join(root, "bin/build-dump")

    def build_dump(*args, stdin: "")
      Open3.capture3({ "RUBYOPT" => nil, "BUNDLE_GEMFILE" => nil }, RbConfig.ruby, *args, stdin_data: stdin, binmode: true)
    end

    def records(file)
      got = []
      header = Openmarket::Dump.read(file) { |record| got << record }
      [ header, got ]
    end

    # Stands in for Openmarket::Wikidata, which the script loads only when it
    # is not there yet: the spec never reaches the network.
    def wikidata_stub(body)
      File.join(dir, "wikidata_stub.rb").tap do |file|
        File.write(file, "module Openmarket; module Wikidata; def self.fetch(names) = #{body}; end; end\n")
      end
    end

    it "is executable" do
      expect(File.executable?(bin)).to be true
    end

    it "builds the dump from a gzipped export on stdin" do
      _, err, status = build_dump(bin, "--off", "-", "--out", out, stdin: export)

      expect(status).to be_success, err
      header, got = records(out)
      expect(header).to include("openmarket" => 1, "license" => "ODbL-1.0")
      expect(got.map { |record| record["name"].is_a?(String) ? record["name"] : record["code"] })
        .to eq([ "BRAHMA", "Cola Co", "0012345000065", "5901234123457", "7891991010023" ])
      expect(err).to include("products 3", "brands 2", "Wrote 5 records")
    end

    it "reads a path, keeps the countries asked for and stops at the limit" do
      _, err, status = build_dump(bin, "--off", path, "--countries", "en:brazil", "--limit", "1", "--out", out)

      expect(status).to be_success, err
      expect(records(out).last.map { |record| record["type"] }).to eq(%w[ brand drink ])
      expect(records(out).last.last["code"]).to eq("7891991010023")
    end

    it "fills the brands in with --wikidata" do
      stub = wikidata_stub(%(names.map { |name| { "type" => "brand", "name" => name, "wikidata" => "Q-\#{name}", "source" => "wikidata" } }))
      _, err, status = build_dump("-r", stub, bin, "--off", path, "--wikidata", "--out", out)

      expect(status).to be_success, err
      brands = records(out).last.select { |record| record["type"] == "brand" }
      expect(brands.map { |record| record["wikidata"] }).to eq([ "Q-BRAHMA", "Q-Cola Co" ])
      expect(err).to include("wikidata 2")
    end

    it "builds without Wikidata when Wikidata fails" do
      stub = wikidata_stub(%(raise SocketError, "getaddrinfo: Name or service not known"))
      _, err, status = build_dump("-r", stub, bin, "--off", path, "--wikidata", "--out", out)

      expect(status).to be_success, err
      expect(err).to include("Wikidata skipped: SocketError")
      expect(records(out).last.filter_map { |record| record["wikidata"] }).to be_empty
    end

    it "fails rather than write a dump with no drinks" do
      _, err, status = build_dump(bin, "--off", "-", "--out", out, stdin: Zlib.gzip(%({"code":"1","categories_tags":["en:beverages"]}\n)))

      expect(status).not_to be_success
      expect(err).to include("No drinks")
      expect(File.exist?(out)).to be false
    end

    it "fails on a broken download, never writing half a dump" do
      _, _, status = build_dump(bin, "--off", "-", "--out", out, stdin: export[0, export.size / 2])

      expect(status).not_to be_success
      expect(File.exist?(out)).to be false
    end

    it "refuses a bad option" do
      _, err, status = build_dump(bin, "--limit", "many")

      expect(status).not_to be_success
      expect(err).to include("invalid argument", "Usage")
    end
  end

  describe "the workflows" do
    def workflow(name) = YAML.load_file(File.join(root, ".github/workflows/#{name}"))

    it "parse" do
      expect(workflow("specs.yml")["jobs"]).not_to be_empty
      expect(workflow("dump.yml")["jobs"]).not_to be_empty
    end

    it "publish the file the restore task downloads" do
      url = File.read(File.join(root, "lib/tasks/openmarket_tasks.rake"), encoding: "UTF-8")[%r{https://github\.com/\S+/releases/latest/download/[\w.]+}]
      steps = workflow("dump.yml").dig("jobs", "dump", "steps").filter_map { |step| step["run"] }.join("\n")

      expect(url).to end_with("/openmarket.ndjson.gz")
      expect(steps).to include("--out openmarket.ndjson.gz", "gh release create \"$tag\" openmarket.ndjson.gz", "--latest")
    end
  end
end
