require "standalone_helper"
require "support/fake_models"
require "openmarket/wikidata"

RSpec.describe Openmarket::Wikidata do
  # Made up, in the shape of a real answer: see its _comment.
  let(:answer) { File.read(File.expand_path("../fixtures/wikidata/brands.json", __dir__), encoding: "UTF-8") }
  let(:nothing) { JSON.generate("head" => { "vars" => [] }, "results" => { "bindings" => [] }) }

  def reply(code, body = nothing, retry_after: nil)
    instance_double(Net::HTTPResponse, code: code.to_s, body: body).tap do |response|
      allow(response).to receive(:[]).with("Retry-After").and_return(retry_after)
    end
  end

  describe ".query" do
    it "asks for each name in each language" do
      sparql = described_class.query([ "Acme Cola", "Água Modelo" ], langs: %w[ en pt ])

      expect(sparql).to include('VALUES ?label { "Acme Cola"@en "Acme Cola"@pt "Água Modelo"@en "Água Modelo"@pt }')
    end

    it "asks only for brands, and for their country code, site and logo" do
      sparql = described_class.query([ "Acme Cola" ])

      expect(sparql).to include("?item rdfs:label ?label", "wdt:P31/wdt:P279* wd:Q431289")
      expect(sparql).to include("wdt:P17 ?country", "wdt:P297 ?iso", "wdt:P856 ?site", "wdt:P154 ?logo")
      expect(sparql.scan(/"Acme Cola"@(\w+)/).flatten).to eq(%w[ en pt es fr de it ])
    end

    it "escapes backslashes, quotes and line breaks" do
      sparql = described_class.query([ "Say \"Hi\" \\ Co\nLtd\r\t" ], langs: %w[ en ])

      expect(sparql).to include('{ "Say \\"Hi\\" \\\\ Co\\nLtd\\r\\t"@en }')
      expect(sparql.lines.grep(/VALUES/).size).to eq(1)
    end

    it "keeps a name that tries to end the string inside it" do
      sparql = described_class.query([ 'x"@en } ?item ?p ?o . { "' ], langs: %w[ en ])

      expect(sparql).to include('{ "x\\"@en } ?item ?p ?o . { \\""@en }')
    end

    it "refuses a language that is not a language tag" do
      expect { described_class.query([ "x" ], langs: [ "en } DROP ALL" ]) }.to raise_error(ArgumentError)
    end
  end

  describe ".records" do
    subject(:records) { described_class.records(answer) }

    def named(name) = records.find { |record| record["name"] == name }

    it "gathers the rows of one item into one record" do
      expect(named("Acme Cola")).to eq(
        "type" => "brand", "name" => "Acme Cola", "wikidata" => "Q900000001", "country" => "US",
        "site" => "https://acme-cola.example.com/",
        "logo" => "https://commons.wikimedia.org/wiki/Special:FilePath/Acme%20Cola%20logo.svg",
        "source" => "wikidata"
      )
    end

    it "gives one record per name" do
      expect(records.map { |record| record["name"] }).to eq([ "Acme Cola", "Cerveja Exemplo", "Água Modelo", "Gin Amostra" ])
    end

    it "drops a name two brands answer to" do
      expect(named("Polaris")).to be_nil
      expect(records.map { |record| record["wikidata"] }).not_to include("Q900000004", "Q900000005")
    end

    it "drops a name whose spellings fold onto two items" do
      row = ->(qid, label) { { "item" => { "value" => "http://www.wikidata.org/entity/#{qid}" }, "label" => { "value" => label } } }
      data = { "results" => { "bindings" => [ row.("Q1", "Antártica"), row.("Q2", "ANTARTICA"), row.("Q3", "Skol") ] } }

      expect(described_class.records(data).map { |record| record["name"] }).to eq([ "Skol" ])
    end

    it "prefers an https site, and keeps a plain http one when that is all there is" do
      expect(named("Cerveja Exemplo")["site"]).to eq("https://cerveja-exemplo.example/")
      expect(named("Gin Amostra")["site"]).to eq("http://gin-amostra.example/")
    end

    it "takes only web links" do
      expect(named("Água Modelo")).not_to include("site", "logo")
    end

    it "names a country only when there is one, with a code" do
      expect(named("Cerveja Exemplo")["country"]).to eq("BR")
      expect(named("Água Modelo")).not_to include("country") # two of them
      expect(named("Gin Amostra")).not_to include("country") # one with no code
    end

    it "skips a row that is not an item with a label" do
      expect(named("Nobody")).to be_nil
    end

    it "takes the answer parsed, too" do
      expect(described_class.records(JSON.parse(answer))).to eq(records)
    end

    it "is empty for an empty answer" do
      expect(described_class.records(nothing)).to eq([])
    end
  end

  describe ".fetch" do
    let(:calls) { [] }

    # Answers in turn, remembering what it was asked. An error class in the
    # turns is the network failing.
    def http(*replies)
      ->(uri, body, headers) do
        calls << { uri: uri, query: URI.decode_www_form(body).to_h["query"], headers: headers }
        found = replies.shift or raise "asked more than expected"
        found.is_a?(Class) ? raise(found) : found
      end
    end

    before { allow(described_class).to receive(:sleep) }

    it "posts the query as a form and asks for SPARQL JSON" do
      described_class.fetch([ "Acme Cola" ], http: http(reply(200))).to_a

      expect(calls.size).to eq(1)
      expect(calls.first[:uri]).to eq(URI("https://query.wikidata.org/sparql"))
      expect(calls.first[:query]).to eq(described_class.query([ "Acme Cola" ]))
      expect(calls.first[:headers]).to include("Accept" => "application/sparql-results+json",
                                               "Content-Type" => "application/x-www-form-urlencoded")
    end

    it "says who is asking" do
      described_class.fetch([ "Acme Cola" ], http: http(reply(200))).to_a

      expect(calls.first[:headers]["User-Agent"]).to match(%r{\Aopenmarket(/\S+)? \(https://github\.com/fireho/openmarket\)\z})
    end

    it "gives the records of the answer" do
      records = described_class.fetch([ "Acme Cola", "Polaris" ], http: http(reply(200, answer))).to_a

      expect(records).to eq(described_class.records(answer))
    end

    it "asks nothing until the records are read" do
      records = described_class.fetch([ "Acme Cola" ], http: http(reply(200)))
      expect(calls).to be_empty

      records.to_a
      expect(calls.size).to eq(1)
    end

    it "asks in batches, and pauses between them" do
      names = %w[ A B C D E ]
      described_class.fetch(names, batch: 2, pause: 0.5, http: http(reply(200), reply(200), reply(200))).to_a

      expect(calls.map { |call| call[:query].scan(/"(\w)"@en/).flatten }).to eq([ %w[ A B ], %w[ C D ], %w[ E ] ])
      expect(described_class).to have_received(:sleep).with(0.5).twice
    end

    it "keeps the spellings of one name in one batch" do
      described_class.fetch([ "Antártica", "Skol", "ANTARTICA" ], batch: 1, http: http(reply(200), reply(200))).to_a

      expect(calls.first[:query]).to include('"Antártica"@en', '"ANTARTICA"@en')
      expect(calls.last[:query]).to include('"Skol"@en')
    end

    it "asks once for a name given twice, and never for a blank one" do
      described_class.fetch([ "Skol", " Skol ", "", nil, "  " ], http: http(reply(200))).to_a

      expect(calls.size).to eq(1)
      expect(calls.first[:query].scan('"Skol"@en').size).to eq(1)
    end

    it "asks nothing for no names" do
      expect(described_class.fetch([ "", nil ], http: http).to_a).to eq([])
      expect(calls).to be_empty
    end

    it "waits as told when throttled, then asks again" do
      records = described_class.fetch([ "Acme Cola" ], http: http(reply(429, "", retry_after: "7"), reply(200, answer))).to_a

      expect(calls.size).to eq(2)
      expect(described_class).to have_received(:sleep).with(7).once
      expect(records).not_to be_empty
    end

    it "backs off on its own when not told how long" do
      described_class.fetch([ "Acme Cola" ], http: http(reply(503), reply(503), reply(200))).to_a

      expect(described_class).to have_received(:sleep).with(5).ordered
      expect(described_class).to have_received(:sleep).with(10).ordered
    end

    it "gives up after a few tries: Wikidata is unavailable" do
      replies = Array.new(4) { reply(429, "", retry_after: "1") }

      expect { described_class.fetch([ "Acme Cola" ], http: http(*replies)).to_a }
        .to raise_error(Openmarket::Wikidata::Unavailable, /429/)
      expect(calls.size).to eq(4)
    end

    it "will not wait for hours" do
      expect { described_class.fetch([ "Acme Cola" ], http: http(reply(429, "", retry_after: "3600"))).to_a }
        .to raise_error(Openmarket::Wikidata::Unavailable, /3600s/)
      expect(described_class).not_to have_received(:sleep)
    end

    it "stops on any other failure, saying what came back" do
      # An Error, not Unavailable: it was this query that failed.
      expect { described_class.fetch([ "Acme Cola" ], http: http(reply(400, "MalformedQueryException: oops\nat ..."))).to_a }
        .to raise_error(an_instance_of(Openmarket::Wikidata::Error), "Wikidata answered 400: MalformedQueryException: oops")
    end

    it "asks again when the network fails" do
      records = described_class.fetch([ "Acme Cola" ], http: http(Net::ReadTimeout, reply(200, answer))).to_a

      expect(calls.size).to eq(2)
      expect(described_class).to have_received(:sleep).with(5).once
      expect(records).not_to be_empty
    end

    it "gives up when the network keeps failing, as it does when throttled" do
      failures = [ Net::OpenTimeout, Errno::ECONNRESET, SocketError, Net::ReadTimeout ]

      expect { described_class.fetch([ "Acme Cola" ], http: http(*failures)).to_a }
        .to raise_error(Openmarket::Wikidata::Unavailable, "Wikidata did not answer: Net::ReadTimeout")
      expect(calls.size).to eq(4)
      expect(described_class).to have_received(:sleep).with(5).ordered
      expect(described_class).to have_received(:sleep).with(10).ordered
      expect(described_class).to have_received(:sleep).with(20).ordered
    end

    it "posts with Net::HTTP when given no client, waiting longer than the service's own 60s" do
      connection = instance_double(Net::HTTP)
      allow(connection).to receive(:post).and_return(reply(200))
      allow(Net::HTTP).to receive(:start) { |*_args, **_options, &block| block.call(connection) }
      described_class.fetch([ "Acme Cola" ]).to_a

      expect(Net::HTTP).to have_received(:start).with("query.wikidata.org", 443, use_ssl: true, read_timeout: 75)
      expect(connection).to have_received(:post)
        .with(URI("https://query.wikidata.org/sparql"), /\Aquery=/, hash_including("User-Agent" => described_class.user_agent))
    end
  end

  describe ".user_agent" do
    it "carries the gem's version when it is loaded" do
      stub_const("Openmarket::VERSION", "1.2.3")

      expect(described_class.user_agent).to eq("openmarket/1.2.3 (https://github.com/fireho/openmarket)")
    end

    it "does without it" do
      hide_const("Openmarket::VERSION")

      expect(described_class.user_agent).to eq("openmarket (https://github.com/fireho/openmarket)")
    end
  end

  describe ".retry_after" do
    it "reads seconds or an HTTP date" do
      expect(described_class.retry_after("12")).to eq(12)
      expect(described_class.retry_after((Time.now + 30).httpdate)).to be_between(29, 30)
      expect(described_class.retry_after((Time.now - 30).httpdate)).to eq(0)
    end

    it "is nil for nothing, or for nonsense" do
      expect(described_class.retry_after(nil)).to be_nil
      expect(described_class.retry_after("soon")).to be_nil
    end
  end

  describe Openmarket::Wikidata::Filler do
    subject(:filler) { described_class.new(batch: 2, http: wikidata) }

    # A pretend Wikidata, as made up as the fixture: it answers from `known`,
    # and with `failing` (a code) for any query that asks about `fails_on`.
    let(:known) do
      {
        "Cerveja Exemplo" => row("Cerveja Exemplo", "Q900000201", site: "https://cerveja-exemplo.example/", iso: "BR"),
        "Ccc" => row("Ccc", "Q900000203"), "Eee" => row("Eee", "Q900000205")
      }
    end
    let(:fails_on) { nil }
    let(:failing) { 500 }
    let(:asked) { [] }
    let(:wikidata) do
      lambda do |_uri, body, _headers|
        names = URI.decode_www_form(body).to_h["query"].scan(/"([^"]*)"@en/).flatten
        asked << names
        if names.include?(fails_on) then reply(failing, "java.util.concurrent.TimeoutException\n\tat ...")
        else reply(200, JSON.generate("results" => { "bindings" => known.values_at(*names).compact }))
        end
      end
    end

    def row(label, qid, site: nil, iso: nil)
      {
        "item" => { "value" => "http://www.wikidata.org/entity/#{qid}" }, "label" => { "value" => label },
        "country" => ({ "value" => "http://www.wikidata.org/entity/Q900000299" } if iso),
        "iso" => ({ "value" => iso } if iso), "site" => ({ "value" => site } if site)
      }.compact
    end

    def brand(name, **attrs) = Fake::Brand.new(name: name, **attrs).tap(&:save)
    def brands(*names) = names.map { |name| brand(name) }

    before do
      Fake.reset!
      allow(Openmarket::Wikidata).to receive(:sleep)
      allow(filler).to receive(:sleep)
    end

    it "writes what Wikidata knows on the brand" do
      exemplo = brand("Cerveja Exemplo")
      filler.call([ exemplo ])

      expect(exemplo).to have_attributes(wikidata: "Q900000201", country: "BR", site: "https://cerveja-exemplo.example/")
      expect(filler.stats).to eq(found: 1)
    end

    it "keeps what a person set" do
      exemplo = brand("Cerveja Exemplo", site: "https://hand-set.example/")
      filler.call([ exemplo ])

      expect(exemplo).to have_attributes(wikidata: "Q900000201", country: "BR", site: "https://hand-set.example/")
    end

    it "writes on the brand it was given, never on another its name finds" do
      # A spelling a person has yet to merge: its name finds the keyed one.
      keyed = brand("CERVEJA EXEMPLO", wikidata: "Q111", site: "https://hand-set.example/")
      spelling = Fake::Brand.legacy("Cerveja Exemplo")
      expect(Fake::Brand.named("Cerveja Exemplo")).to equal(keyed)

      filler.call([ spelling ])

      expect(keyed).to have_attributes(wikidata: "Q111", site: "https://hand-set.example/", country: nil)
      expect(filler.stats).to eq(invalid: 1) # it has no key of its own to save with
      expect(filler.errors).to eq([ "Cerveja Exemplo: Key is taken" ])
    end

    it "takes nothing from another item than the one a brand already is" do
      exemplo = brand("Cerveja Exemplo", wikidata: "Q900000999")
      filler.call([ exemplo ])

      expect(exemplo).to have_attributes(wikidata: "Q900000999", country: nil, site: nil)
      expect(filler.stats).to eq(missing: 1)
    end

    it "asks a batch at a time, pausing between them, and says how far it got" do
      all = brands("Aaa", "Bbb", "Ccc", "Ddd", "Eee")
      filler.call(all)

      expect(asked).to eq([ %w[ Aaa Bbb ], %w[ Ccc Ddd ], %w[ Eee ] ])
      expect(filler).to have_received(:sleep).with(1.0).twice
      expect(filler.stats).to eq(found: 2, missing: 3)
      expect(filler.last).to eq("Eee")
    end

    context "when Wikidata fails on a batch" do
      let(:fails_on) { "Ccc" }

      it "passes it over and goes on with the rest" do
        all = brands("Aaa", "Bbb", "Ccc", "Ddd", "Eee")
        filler.call(all)

        expect(asked).to eq([ %w[ Aaa Bbb ], %w[ Ccc Ddd ], %w[ Eee ] ])
        expect(all.last.wikidata).to eq("Q900000205")
        expect(filler.stats).to eq(missing: 2, skipped: 2, found: 1)
        expect(filler.errors).to eq([ "skipped Ccc .. Ddd: Wikidata answered 500: java.util.concurrent.TimeoutException" ])
        expect(filler.last).to eq("Eee")
      end
    end

    context "when Wikidata is unavailable" do
      let(:known) { { "Bbb" => row("Bbb", "Q900000202") } }
      let(:fails_on) { "Ccc" }
      let(:failing) { 429 }

      it "stops, keeping what it wrote and the last brand it got to" do
        all = brands("Aaa", "Bbb", "Ccc", "Ddd", "Eee")

        expect { filler.call(all) }.to raise_error(Openmarket::Wikidata::Unavailable, /429/)
        expect(all[1].wikidata).to eq("Q900000202")
        expect(filler.stats).to eq(missing: 1, found: 1)
        expect(filler.last).to eq("Bbb")
        expect(asked).not_to include(%w[ Eee ])
      end
    end

    it "tells progress after each batch" do
      heard = []
      described_class.new(batch: 2, http: wikidata, pause: 0, progress: ->(stats) { heard << stats.dup }).call(brands("Aaa", "Ccc", "Eee"))

      expect(heard).to eq([ { missing: 1, found: 1 }, { missing: 1, found: 2 } ])
    end
  end
end
