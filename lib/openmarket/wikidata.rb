require "json"
require "net/http"
require "time"
require "uri"
require "openmarket/text"

module Openmarket
  # What Wikidata knows about a brand: its id (QID), the country it is from,
  # its official site, its logo. Wikidata is CC0, so these facts can go into
  # the open dump as they are.
  #
  #   Openmarket::Wikidata.fetch([ "Brahma", "Skol" ]).each { |record| ... }
  #   # => {"type"=>"brand","name"=>"Brahma","wikidata"=>"Q...","country"=>"BR","site"=>"https://...","source"=>"wikidata"}
  #
  # A name meets an item only by an exact label, and only an item that is a
  # brand. A name two brands answer to is left out: a wrong QID in an open
  # catalogue spreads, a missing one is only missing.
  #
  # The ids, as Wikidata numbers them: Q431289 brand, P31 instance of, P279
  # subclass of, P17 country, P297 ISO 3166-1 alpha-2 code, P856 official
  # website, P154 logo image.
  module Wikidata
    ENDPOINT = "https://query.wikidata.org/sparql"
    LANGS = %w[ en pt es fr de it ].freeze
    SOURCE = "wikidata".freeze

    # The query service throttles with 429 (or 503) and a Retry-After. We wait
    # as told, a few times, then stop: a client that keeps asking gets banned.
    RETRY = [ 429, 503 ].freeze
    RETRIES = 3
    BACKOFF = 5    # seconds, doubled each time, when there is no Retry-After
    MAX_WAIT = 120 # told to wait longer than this, we try another day

    # A name goes into the query inside "...": these would end it or bend it.
    ESCAPES = { "\\" => "\\\\", "\"" => "\\\"", "\n" => "\\n", "\r" => "\\r", "\t" => "\\t", "\b" => "\\b", "\f" => "\\f" }.freeze
    SPECIAL = Regexp.union(ESCAPES.keys)

    ENTITY = %r{\Ahttps?://www\.wikidata\.org/entity/(Q\d+)\z}

    # (uri, form body, headers) -> response. A spec hands in its own.
    NET_HTTP = ->(uri, body, headers) { Net::HTTP.post(uri, body, headers) }

    class Error < StandardError; end

    module_function

    # Labels are language-tagged, so each name is asked in each language: an
    # exact match on the index is fast, a filter over every label never ends.
    def query(names, langs: LANGS)
      langs.each { |lang| raise ArgumentError, "not a language tag: #{lang.inspect}" unless lang.to_s.match?(/\A[a-z]+(-[a-z0-9]+)*\z/i) }
      labels = names.product(langs).map { |name, lang| "#{literal(name)}@#{lang}" }

      <<~SPARQL
        PREFIX wd: <http://www.wikidata.org/entity/>
        PREFIX wdt: <http://www.wikidata.org/prop/direct/>
        PREFIX rdfs: <http://www.w3.org/2000/01/rdf-schema#>
        SELECT DISTINCT ?item ?label ?country ?iso ?site ?logo WHERE {
          VALUES ?label { #{labels.join(' ')} }
          ?item rdfs:label ?label ;
                wdt:P31/wdt:P279* wd:Q431289 .
          OPTIONAL { ?item wdt:P17 ?country . OPTIONAL { ?country wdt:P297 ?iso } }
          OPTIONAL { ?item wdt:P856 ?site }
          OPTIONAL { ?item wdt:P154 ?logo }
        }
      SPARQL
    end

    def literal(text) = "\"#{text.to_s.gsub(SPECIAL, ESCAPES)}\""

    # A SPARQL JSON answer (the body, or it parsed) as brand records, one per
    # name. One item comes back as many rows — a row per label, country, site
    # and logo — so rows are gathered by the name they matched, folded.
    def records(json)
      data = json.is_a?(String) ? JSON.parse(json) : json
      matches = Array(data.dig("results", "bindings")).filter_map do |row|
        qid = value(row, "item")&.[](ENTITY, 1)
        label = value(row, "label")
        [ Text.fold(label), qid, label, row ] if qid && label
      end

      matches.group_by(&:first).values.filter_map do |found|
        qids = found.map { |_fold, qid| qid }.uniq
        next if qids.size > 1 # two brands answer to this name: never guess which

        rows = found.map(&:last)
        {
          "type" => "brand", "name" => found.map { |_fold, _qid, label| label }.min, "wikidata" => qids.first,
          "country" => country(rows), "site" => link(rows, "site"), "logo" => link(rows, "logo"), "source" => SOURCE
        }.compact
      end
    end

    # Brand records for these names, asked a batch at a time. Lazy: nothing is
    # asked until the records are read. Spellings of one name ("Antártica",
    # "Antartica") share a batch, or no answer would show both of them together.
    def fetch(names, batch: 100, http: nil, pause: 1.0)
      http ||= NET_HTTP
      groups = names.map { |name| name.to_s.strip }.reject(&:empty?).uniq.group_by { |name| Text.fold(name) }.values

      Enumerator.new do |out|
        groups.each_slice(batch).with_index do |slice, index|
          sleep(pause) if index.positive? && pause.positive?
          records(post(query(slice.flatten), http)).each { |record| out << record }
        end
      end
    end

    def post(query, http)
      body = URI.encode_www_form(query: query)
      tries = 0
      loop do
        response = http.call(URI(ENDPOINT), body, headers)
        code = response.code.to_i
        return response.body if code.between?(200, 299)
        raise Error, "Wikidata answered #{code}: #{response.body.to_s.lines.first.to_s.strip[0, 200]}" unless RETRY.include?(code) && tries < RETRIES

        wait = retry_after(response["Retry-After"]) || BACKOFF * 2**tries
        raise Error, "Wikidata asks us to wait #{wait}s: try again later" if wait > MAX_WAIT

        tries += 1
        sleep(wait)
      end
    end

    def headers
      {
        "Accept" => "application/sparql-results+json",
        "Content-Type" => "application/x-www-form-urlencoded",
        "User-Agent" => user_agent
      }
    end

    # Wikimedia refuses clients that do not say who they are and where to
    # find the people behind them.
    def user_agent
      version = "/#{Openmarket::VERSION}" if defined?(Openmarket::VERSION)
      "openmarket#{version} (https://github.com/fireho/openmarket)"
    end

    # Seconds, or an HTTP date. nil for none, or for one that will not read.
    def retry_after(value)
      text = value.to_s.strip
      return if text.empty?
      return text.to_i if text.match?(/\A\d+\z/)

      [ (Time.httpdate(text) - Time.now).ceil, 0 ].max
    rescue ArgumentError
      nil
    end

    # Only when the item names one country and it has a code: a brand "from"
    # two countries is from neither, as far as we can tell.
    def country(rows)
      countries = rows.filter_map { |row| value(row, "country") }.uniq
      codes = rows.filter_map { |row| value(row, "iso")&.strip&.upcase }.uniq
      codes.first if countries.size == 1 && codes.size == 1 && codes.first.match?(/\A[A-Z]{2}\z/)
    end

    # A web link, or nil. Logos come as http://commons.wikimedia.org/wiki/Special:FilePath/...,
    # which serves the same file over https. An item with several (a site per
    # language) gives the https one first, then the first in order, so two
    # runs give the same answer.
    def link(rows, key)
      rows.filter_map { |row| value(row, key) }
          .map { |url| url.sub(%r{\Ahttp://commons\.wikimedia\.org/}, "https://commons.wikimedia.org/") }
          .select { |url| url.match?(%r{\Ahttps?://[^\s/]+}i) }
          .min_by { |url| [ url.start_with?("https:") ? 0 : 1, url ] }
    end

    def value(row, key)
      found = row[key] if row.is_a?(Hash)
      found["value"] if found.is_a?(Hash) && found["value"].is_a?(String)
    end
  end
end
