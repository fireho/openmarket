module Openmarket
  # Names as people type them, folded so they meet: "Antártica", "ANTARTICA "
  # and "antartica" are one brand. Lookup keys only — never shown.
  module Text
    # Accents come off Latin, Greek and Cyrillic letters only. In Japanese or
    # Thai the marks are part of the letter: ビール is not ヒール.
    ACCENTS = /(?<=[\p{Latin}\p{Greek}\p{Cyrillic}])\p{Mn}+/

    def self.fold(text)
      text.to_s.scrub("").unicode_normalize(:nfkd).gsub(ACCENTS, "").unicode_normalize(:nfc)
          .downcase.gsub(/\s+/, " ").strip
    end

    # The words of a text, folded: what a search for "antar orig" matches
    # "Antártica Original" by.
    def self.tokens(*texts)
      texts.flatten.flat_map { |text| fold(text).split(/[^\p{Alnum}]+/) }.reject(&:empty?).uniq
    end
  end
end
