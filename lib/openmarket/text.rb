module Openmarket
  # Names as people type them, folded so they meet: "Antártica", "ANTARTICA "
  # and "antartica" are one brand. Lookup keys only — never shown.
  module Text
    # Accents come off Latin, Greek and Cyrillic letters only. In Japanese or
    # Thai the marks are part of the letter: ビール is not ヒール.
    ACCENTS = /(?<=[\p{Latin}\p{Greek}\p{Cyrillic}])\p{Mn}+/

    # Invisible characters a paste brings along — a BOM, a zero-width space, a
    # soft hyphen — are no part of a name. Every brand key, the builder's and
    # the model's alike, comes through here, so they all agree.
    INVISIBLE = /\p{Cf}/

    def self.fold(text)
      text.to_s.scrub("").unicode_normalize(:nfkd).gsub(ACCENTS, "").gsub(INVISIBLE, "")
          .unicode_normalize(:nfc).downcase.gsub(/[[:space:]]+/, " ").strip
    end

    # The words of a text, folded: what a search for "antar orig" matches
    # "Antártica Original" by.
    def self.tokens(*texts)
      texts.flatten.flat_map { |text| fold(text).split(/[^\p{Alnum}]+/) }.reject(&:empty?).uniq
    end
  end
end
