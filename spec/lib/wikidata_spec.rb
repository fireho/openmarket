require "standalone_helper"
require "openmarket/wikidata"

RSpec.describe Openmarket::Wikidata do
  # Made up, in the shape of a real answer: see its _comment.
  let(:answer) { File.read(File.expand_path("../fixtures/wikidata/brands.json", __dir__)) }
  let(:nothing) { JSON.generate("head" => { "vars" => [] }, "results" => { "bindings" => [] }) }

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

    def reply(code, body = nothing, retry_after: nil)
      instance_double(Net::HTTPResponse, code: code.to_s, body: body).tap do |response|
        allow(response).to receive(:[]).with("Retry-After").and_return(retry_after)
      end
    end

    # Answers in turn, remembering what it was asked.
    def http(*replies)
      ->(uri, body, headers) do
        calls << { uri: uri, query: URI.decode_www_form(body).to_h["query"], headers: headers }
        replies.shift or raise "asked more than expected"
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

    it "gives up after a few tries" do
      replies = Array.new(4) { reply(429, "", retry_after: "1") }

      expect { described_class.fetch([ "Acme Cola" ], http: http(*replies)).to_a }
        .to raise_error(Openmarket::Wikidata::Error, /429/)
      expect(calls.size).to eq(4)
    end

    it "will not wait for hours" do
      expect { described_class.fetch([ "Acme Cola" ], http: http(reply(429, "", retry_after: "3600"))).to_a }
        .to raise_error(Openmarket::Wikidata::Error, /3600s/)
      expect(described_class).not_to have_received(:sleep)
    end

    it "stops on any other failure, saying what came back" do
      expect { described_class.fetch([ "Acme Cola" ], http: http(reply(400, "MalformedQueryException: oops\nat ..."))).to_a }
        .to raise_error(Openmarket::Wikidata::Error, "Wikidata answered 400: MalformedQueryException: oops")
    end

    it "posts with Net::HTTP when given no client" do
      allow(Net::HTTP).to receive(:post).and_return(reply(200))
      described_class.fetch([ "Acme Cola" ]).to_a

      expect(Net::HTTP).to have_received(:post)
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
end
