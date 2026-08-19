# frozen_string_literal: true

module RemLint
  # A run of Remind code carved out of a file, together with where it sat.
  #
  # `line_offset` is the number of physical lines that preceded this run in the
  # file on disk -- zero for a plain `.rem` file, and the line number of the
  # heredoc's opener for Remind embedded in a shell script. Every line number
  # the linter reports is computed through this offset, so an offence inside
  # the third heredoc of a shell script points at the real line of that script
  # rather than at line 4 of an anonymous fragment.
  Source = Struct.new(
    :path,
    :text,
    :line_offset,
    :description,
    keyword_init: true,
  ) do
    def initialize(path:, text:, line_offset: 0, description: nil)
      super
    end

    def lines
      text.lines
    end

    # How to name this source in a message when a file yields more than one.
    def label
      if description
        "#{path} (#{description})"
      else
        path
      end
    end
  end
end
