require 'rdf/kv/version'

class RDF::KV
  private

  # some xml grammar
  NCNSCHAR = 'A-Za-z_\\u00c0-\\u00d6\\u00d8-\\u00f6\\u00f8-\\u2ff' \
    '\\u0370-\\u037d\\u037f-\\u1fff\\u200c-\\u200d\\u2070-\\u218f' \
    '\\u2c00-\\u2fef\\u3001-\\ud7ff\\uf900-\\ufdcf\\ufdf0-\\ufffd' \
    '\\u10000-\\ueffff'.freeze
  NSCHAR     = "[:#{NCNSCHAR}]".freeze
  NCNAMECHAR = "-.0-9#{NCNSCHAR}\\u00b7\\u0300-\\u036f\\u203f-\\u2040".freeze
  NCNAME     = "[#{NCNSCHAR}][#{NCNAMECHAR}]*".freeze

  # the actual rdf-kv grammar
  MODIFIER     = '(?:[!=+-]|[+-]!|![+-])'.freeze
  PREFIX       = "(?:#{NCNAME}|[A-Za-z][0-9A-Za-z.+-]*)".freeze
  TERM         = "(?:#{PREFIX}:\\S*)".freeze
  RFC5646      = '(?:[A-Za-z]+(?:-[0-9A-Za-z]+)*'.freeze
  DESIGNATOR   = "(?:[:_']|@#{RFC5646}|\\^#{TERM})".freeze
  DECLARATION  = "^\\s*\\$\\s+(#{NCNAME})(?:\\s+(\\$))?\s*$".freeze
  MACRO        = "(?:\\$\\{(#{NCNAME})\\}|\\$(#{NCNAME}))".freeze
  NOT_MACRO    = "(?:(?!\\$#{NCNAME}|\\$\\{(#{NCNAME})\\}).)*".freeze
  MACROS       = "(#{NOT_MACRO})(?:#{MACRO})?(#{NOT_MACRO})".freeze
  PARTIAL_STMT = "^\\s*(?:(#{MODIFIER})\\s+)?" \
    "(?:(#{TERM})(?:\\s+(#{TERM}))?(?:\\s+(#{DESIGNATOR}))?|" \
    "(#{TERM})\\s+(#{DESIGNATOR})\\s+(#{TERM})|" \
    "(#{TERM})\\s+(#{TERM})(?:\\s+(#{DESIGNATOR}))?\\s(#{TERM}))" \
    "(?:\\s+(\\$))?\\s*$".freeze

  MAP = %i[modifier term1 term2 esignator term1 designator graph
    term1 term2 designator graph deref]

  # these should be instance_eval'd
  SPECIALS = {
    subject: -> val {
    },
    graph:   -> val {
    },
    prefix:  -> val {
    },
  }

  # not sure
  GENERATED = {
    new_uuid:     [[-> {}, 0]],
    new_uuid_urn: [[-> {}, 0]],
    new_bnode:    [[-> {}, 0]],
  }

  def deref_content
  end

  def massage_macros
  end

  public
end
