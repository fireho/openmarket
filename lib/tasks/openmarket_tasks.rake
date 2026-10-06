require "fileutils"
require "shellwords"

namespace :openmarket do
  release = "https://github.com/fireho/openmarket/releases/latest/download/openmarket.ndjson.gz"

  # A path as given, or a URL fetched into tmp/downloads/ first — never over
  # tmp/openmarket.ndjson.gz, which is where `dump` writes yours.
  def openmarket_file(given, default_url: nil)
    given = given.presence || default_url
    abort "FILE=path|url is needed" unless given
    return given unless given.start_with?("http")

    FileUtils.mkdir_p("tmp/downloads")
    dest = File.join("tmp/downloads", File.basename(URI(given).path))
    puts "Downloading #{given} -> #{dest}"
    Openmarket::Download.fetch(given, dest)
  end

  def openmarket_counts(stats) = stats.sort.map { |key, n| "#{key} #{n}" }.join(", ")

  def openmarket_progress(label) = ->(stats) { warn "#{label}: #{openmarket_counts(stats)}" }

  # Bring rows from before the open catalogue up to it, then index: no stored
  # null codes, a key on every brand, search words on every product. The old
  # index made a code unique across orgs too; it gives way to one per owner.
  def openmarket_indexes
    ::Product.where(code: nil).unset(:code)
    clashes = ::Brand.backfill_keys
    warn "Brands spelled like another, left without a key — merge them: #{clashes.join(', ')}" if clashes.any?

    old = ::Product.collection.indexes.find { |index| index["name"] == "code_1" }
    ::Product.collection.indexes.drop_one("code_1") if old && old["unique"]

    ::Brand.create_indexes
    ::Product.create_indexes
    ::Product.backfill_tokens
  end

  desc "Write the shared catalogue as NDJSON. FILE=tmp/openmarket.ndjson.gz"
  task dump: :environment do
    path = ENV.fetch("FILE", "tmp/openmarket.ndjson.gz")
    FileUtils.mkdir_p(File.dirname(path))
    puts "Wrote #{Openmarket::Catalogue.dump(path)} records to #{path}"
  end

  desc "Load a dump into the shared catalogue. FILE=path|url (default: the latest GitHub release, else the snapshot in the gem) OVERWRITE=1 to replace rows already there"
  task restore: :environment do
    path =
      begin
        openmarket_file(ENV["FILE"], default_url: release)
      rescue StandardError => e
        # Asked for nothing in particular and the release is out of reach (no
        # network, or no release yet): the gem carries a snapshot of its own.
        raise if ENV["FILE"].present?

        warn "No release to download (#{e.message}): loading the snapshot in the gem"
        Openmarket::SNAPSHOT
      end
    openmarket_indexes
    stats = Openmarket::Catalogue.restore(path, overwrite: ENV["OVERWRITE"].present?, progress: openmarket_progress("restore"))
    puts "Done: #{openmarket_counts(stats)}"
  end

  namespace :import do
    desc "Import drinks from Open Food Facts. FILE=path|url (default: their jsonl.gz, several GB) COUNTRIES=en:brazil,en:argentina LIMIT=1000"
    task off: :environment do
      path = openmarket_file(ENV["FILE"], default_url: Openmarket::OpenFoodFacts::DUMP_URL)
      countries = ENV["COUNTRIES"].to_s.split(",").map(&:strip).reject(&:empty?).presence
      limit = ENV["LIMIT"].presence&.to_i

      openmarket_indexes
      importer = Openmarket::Importer.new(progress: openmarket_progress("off"))
      importer.call(Openmarket::OpenFoodFacts.each(path, countries: countries, limit: limit))

      puts "Done: #{openmarket_counts(importer.stats)}"
      importer.errors.first(10).each { |error| warn "  invalid #{error}" }
    end

    desc "Fill in what Wikidata (CC0) knows — id, country, site, logo — on brands without a wikidata id. LIMIT=500 AFTER=name (go on after that brand)"
    task wikidata: :environment do
      openmarket_indexes
      # In name order, so a run that stops can go on AFTER the last brand it
      # got to. A brand without a key is a spelling of another, waiting to be
      # merged (named just above): it would not save, so it is not asked about.
      brands = ::Brand.where(key: { "$ne" => nil }, wikidata: { "$in" => [ nil, "" ] }).order_by(name: 1)
      # ENV comes in the locale's encoding (binary under LANG=C): names are UTF-8.
      after = ENV["AFTER"].to_s.dup.force_encoding(Encoding::UTF_8).scrub.presence
      brands = brands.where(name: { "$gt" => after }) if after
      limit = ENV["LIMIT"].presence&.to_i
      brands = brands.limit(limit) if limit
      brands = brands.to_a

      filler = Openmarket::Wikidata::Filler.new(progress: openmarket_progress("wikidata"))
      begin
        filler.call(brands)
      rescue Openmarket::Wikidata::Unavailable => e
        stopped = e.message
      end

      filler.errors.each { |error| warn "  #{error}" }
      # What was written is saved. A brand Wikidata does not know stays blank,
      # so a run without AFTER would ask about the same ones again.
      after = filler.last || after
      go_on = " Go on with AFTER=#{Shellwords.escape(after)}" if after && (stopped || brands.size == limit)
      summary = "#{openmarket_counts(filler.stats).presence || 'none'} of #{brands.size} brands.#{go_on}"
      abort "Stopped: #{stopped}\n#{summary}" if stopped
      puts "Done: #{summary}"
    end
  end
end
