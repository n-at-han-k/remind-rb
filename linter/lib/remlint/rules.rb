# frozen_string_literal: true

require_relative "rule"

# Requiring a rule file registers the rule, so this list is the only place a
# new rule has to be mentioned. Sorted by name to make an addition a one-line
# diff rather than an argument about ordering.
require_relative "rules/color_component_range"
require_relative "rules/dangling_continuation"
require_relative "rules/function_arity"
require_relative "rules/keyword_case"
require_relative "rules/license_header"
require_relative "rules/line_length"
require_relative "rules/syntax"
require_relative "rules/system_variable_assignment"
require_relative "rules/trailing_whitespace"
require_relative "rules/unbalanced_blocks"
require_relative "rules/unbalanced_delimiters"
require_relative "rules/unknown_system_variable"
