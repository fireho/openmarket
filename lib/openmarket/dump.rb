require "json"
require "zlib"

module Openmarket
  # The dump file: NDJSON, one record per line, gzipped when the name ends in
  # .gz. Anyone can read it with `zcat openmarket.ndjson.gz | jq` — no Mongo
  # needed. This module is the format only; Catalogue moves records between
  # the file and the database.
  #
  #   {"openmarket":1,"generated_at":"2026-10-05","license":"ODbL-1.0", ...}
  #   {"type":"brand","name":"Brahma"}
  #   {"type":"drink","code":"7891991010023","name":{"pt":"Cerveja Brahma"},"brand":"Brahma",...}
  #
  # Brands first, then products, each ordered (name, code) so two dumps of the
  # same catalogue are the same bytes and a diff shows only what changed.
  # Records are keyed by what the world knows — a code, a name — never by a
  # Mongo id, so a dump loads into any database. Empty fields are left out.
  module Dump
    VERSION = 1

    class Error < StandardError; end

    def self.header
      {
        "openmarket" => VERSION,
        "generated_at" => Time.now.utc.strftime("%Y-%m-%d"),
        "license" => "ODbL-1.0",
        "attribution" => "Contains information from Open Food Facts (https://world.openfoodfacts.org), " \
                         "made available under the Open Database License 1.0",
        "terms" => "https://opendatacommons.org/licenses/odbl/1-0/"
      }
    end

    # Writes the header and then every record; returns how many records.
    def self.write(target, records)
      count = 0
      writing(target) do |io|
        io.puts JSON.generate(header)
        records.each do |record|
          io.puts JSON.generate(slim(record))
          count += 1
        end
      end
      count
    end

    # Yields each record after the header; returns the header.
    def self.read(source)
      head = nil
      reading(source) do |io|
        io.each_line do |line|
          next if line.strip.empty?

          data = JSON.parse(line.scrub)
          if head.nil?
            head = data
            raise Error, "not an openmarket dump" unless head.is_a?(Hash) && head.key?("openmarket")
            raise Error, "dump format #{head['openmarket']} is newer than #{VERSION}" if head["openmarket"] > VERSION
          else
            yield data
          end
        end
      end
      raise Error, "empty dump" unless head
      head
    end

    def self.slim(record)
      record.reject { |_, value| value.nil? || (value.respond_to?(:empty?) && value.empty?) }
    end

    # A dump that fails halfway must not look like a finished one, so it is
    # written beside the target and moved into place only when complete.
    def self.writing(target, &block)
      return yield(target) if target.respond_to?(:puts)

      path = target.to_s
      partial = "#{path}.partial"
      if path.end_with?(".gz")
        Zlib::GzipWriter.open(partial) do |gz|
          gz.mtime = 0 # same catalogue, same bytes
          yield gz
        end
      else
        File.open(partial, "w:UTF-8", &block)
      end
      File.rename(partial, path)
    ensure
      File.delete(partial) if partial && File.exist?(partial)
    end

    def self.reading(source, &block)
      return yield(source) if source.respond_to?(:read)

      path = source.to_s
      if path.end_with?(".gz")
        Zlib::GzipReader.open(path, external_encoding: Encoding::UTF_8, &block)
      else
        File.open(path, "r:UTF-8", &block)
      end
    end
  end
end
