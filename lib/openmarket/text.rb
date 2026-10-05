module Openmarket
  # Names as people type them, folded so they meet: "Antártica", "ANTARCTICA "
  # and "antarctica" are one brand. Lookup keys only — never shown.
  module Text
    def self.fold(text)
      text.to_s.unicode_normalize(:nfkd).gsub(/\p{Mn}/, "").downcase.gsub(/\s+/, " ").strip
    end
  end
end
