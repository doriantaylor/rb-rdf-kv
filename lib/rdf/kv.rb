require 'rdf/kv/version'

require 'rdf'
require 'uri'
require 'uuidtools'
require 'uuid-ncname'

class RDF::KV
  private

  # some xml grammar
  NCNSCHAR = 'A-Za-z_\\u00c0-\\u00d6\\u00d8-\\u00f6\\u00f8-\\u02ff' \
    '\\u0370-\\u037d\\u037f-\\u1fff\\u200c-\\u200d\\u2070-\\u218f' \
    '\\u2c00-\\u2fef\\u3001-\\ud7ff\\uf900-\\ufdcf\\ufdf0-\\ufffd' \
    '\\u{10000}-\\u{effff}'.freeze
  NSCHAR     = "[:#{NCNSCHAR}]".freeze
  NCNAMECHAR = "-.0-9#{NCNSCHAR}\\u00b7\\u0300-\\u036f\\u203f-\\u2040".freeze
  NCNAME     = "[#{NCNSCHAR}][#{NCNAMECHAR}]*".freeze

  # the actual rdf-kv grammar
  MODIFIER     = '(?:[!=+-]|[+-]!|![+-])'.freeze
  PREFIX       = "(?:#{NCNAME}|[A-Za-z][0-9A-Za-z.+-]*)".freeze
  TERM         = "(?:#{PREFIX}:\\S*)".freeze
  RFC5646      = '(?:[A-Za-z]+(?:-[0-9A-Za-z]+)*)'.freeze
  DESIGNATOR   = "(?:[:_']|@#{RFC5646}|\\^#{TERM})".freeze
  DECLARATION  = "^\\s*\\$\\s+(#{NCNAME})(?:\\s+(\\$))?\s*$".freeze
  MACRO        = "(?:\\$\\{(#{NCNAME})\\}|\\$(#{NCNAME}))".freeze
  NOT_MACRO    = "(?:(?!\\$#{NCNAME}|\\$\\{#{NCNAME}\\}).)*".freeze
  MACROS       = "(#{NOT_MACRO})(?:#{MACRO})?(#{NOT_MACRO})".freeze
  PARTIAL_STMT = "^\\s*(?:(#{MODIFIER})\\s+)?" \
    "(?:(#{TERM})(?:\\s+(#{TERM}))?(?:\\s+(#{DESIGNATOR}))?|" \
    "(#{TERM})\\s+(#{DESIGNATOR})\\s+(#{TERM})|" \
    "(#{TERM})\\s+(#{TERM})(?:\\s+(#{DESIGNATOR}))?\\s(#{TERM}))" \
    "(?:\\s+(\\$))?\\s*$".freeze

  GRAMMAR = /#{PARTIAL_STMT}/o
  MAP     = %i[modifier term1 term2 designator term1 designator graph
             term1 term2 designator graph deref].freeze

  # these should be instance_exec'd
  SPECIALS = {
    SUBJECT: -> val {
      @subject = resolve_term val[-1] unless val.empty? },
    GRAPH:   -> val {
      @graph = resolve_term val[-1] unless val.empty? },
    PREFIX:  -> val {
      val.each do |v, _|
        next unless m = /^\s*(#{NCNAME}):\s+(.*)$/o.match(v)
        prefix, uri = m.captures
        @prefixes[prefix.to_sym] = RDF::Vocabulary.new uri
      end
    },
  }.freeze

  # macros are initially represented as a pair: the macro value and a
  # flag denoting whether or not the macro itself contains macros and to
  # try to dereference it.
  GENERATED = {
    NEW_UUID:     [[-> { UUIDTools::UUID.random_create.to_s   }, false]],
    NEW_UUID_URN: [[-> { UUIDTools::UUID.random_create.to_uri }, false]],
    NEW_BNODE:    [[-> { "_:#{UUID::NCName.to_ncname_64(
          UUIDTools::UUID.random_create.to_s, version: 1) }" }, false]],
  }.freeze

  # just the classics
  DEFAULT_NS = {
    rdf:  RDF::RDFV,
    rdfs: RDF::RDFS,
    owl:  RDF::OWL,
    xsd:  RDF::XSD,
  }.freeze

  # Given a (massaged) set of macros, dereference the given array of
  # strings and return it.
  def deref_content strings, macros
    strings = [strings] unless strings.is_a? Array
    # bail out early if there is nothing to do
    return strings unless strings.any? { |s| /#{MACRO}/o.match s }
    out = []
    strings.each do |s|
      # chunks are parallel output; each element is a value
      chunks = []
      s.scan(/\G#{MACROS}/o) do |m|
        pre   = m.first
        macro = m[1] || m[2]
        post  = m[3]

        # skip if there was no macro
        unless macro
          # nothing to do
          next if pre + post == ""
          chunks = chunks.empty? ? [pre, post] : chunks.map do |x|
            "#{x}#{pre}#{post}"
          end
          next
        end

        # dereference the macro (or noop if unbound)
        macro = macro.to_sym
        x = if macros[macro]
              macros[macro].map do |m|
                '%s%s%s' % [pre, m.respond_to?(:call) ? m.call : m, post]
              end
            else
              # this is a noop
              ["#{pre}$#{macro}#{post}"]
            end

        # initialize chunks
        if chunks.empty?
          chunks = x
          next
        elsif !x.empty?
          # replace chunks with the product of itself and x
          y = []
          chunks.each { |c| x.each { |d| y << "#{c}#{d}" } }
          chunks = y
        end
      end

      out.concat chunks
    end

    out
  end

  # Given the structure of macro declarations, dereference any
  # recursively-defined macros, and return a new structure with a key
  # and array of _values_, rather than an array of `[value, deref]`
  # pairs.
  def massage_macros macros
    seen = {}
    done = GENERATED.transform_values { |v| v.map { |w| w.first } }
    pending = macros.reject { |k, _| GENERATED.key? k }
    queue   = pending.keys.slice 0..0 # take a zero-or-one-element slice

    until queue.empty?
      k = queue.shift
      seen[k] = true

      vals = macros[k]

      # done and pending macros within the macros
      dm = {}
      pm = {}

      vals.each do |pair|
        val, deref = pair

        next unless deref

        if deref.is_a? Array
          deref.each { |m| done[m] ? dm[m] = true : pm[m] = true }
        else
          m = {}
          val.scan(/#{MACRO}/o).compact.each do |x|
            x = x.to_sym
            next unless macros[x]
            raise "Self-reference found: #{x}" if x == k

            m[x] = true

            done[m] ? dm[m] = true : pm[m] = true
          end

          # replace the deref flag with the elements to deref with
          pair[1] = m.empty? ? false : m.keys.sort
        end
      end

      # macro values have pending matches
      if !pm.empty?
        q = []
        pm.keys.each do |m|
          raise "Cycle detected between #{k} and #{m}" if seen[m]
          q << m
        end

        # put the current key back on the queue but put the dependencies first
        queue = q + [k] + queue
        next
      end

      unless dm.empty?
        done[k] = deref_content vals, done
      else
        done[k] = vals.map(&:first)
      end

      # remember to remove this guy or we'll loop forever
      pending.delete k

      # replenish the queue with another pending object
      queue << pending.keys.first if queue.empty? and !pending.keys.empty?
    end

    done
  end

  # unconditionally return a uri or bnode
  def resolve_term term
    return term if term.is_a? RDF::Term
    term = term.to_s

    # bnode ahoy
    return RDF::Node.new term.delete_prefix '_:' if term.start_with? '_:'

    # ugh now we gotta do urls
    if m = /^(#{NCNAME}):(\S*)$/o.match(term)
      prefix, slug = m.captures
      if !slug.start_with?(?/) and vocab = prefixes[prefix.to_sym]
        return vocab[slug]
      end
    end

    # now resolve against base
    RDF::URI((URI(subject.to_s) + term).to_s)
  end

  # may accept and respond with nil
  def coerce_term token, hint = nil, langdt = nil
    return unless token
    return token if token.is_a? RDF::Term
    hint ||= ?:
    term = nil
    if [?:, ?_].include? hint
      return if token.empty?
      token = '_:' + token if hint == ?_ and !token.start_with? '_:'
      term = resolve_term token
    elsif hint == ?@
      term = RDF::Literal(token, language: langdt.to_s.to_sym)
    elsif hint == ?^
      raise 'datatype must be an RDF::Resource' unless
        langdt.is_a? RDF::Resource
      term = RDF::Literal(token, datatype: langdt)
    elsif hint == ?'
      term = RDF::Literal(token)
    else
      raise ArgumentError, "Unrecognized hint (#{hint})"
    end

    # call the callback if we have one
    term = callback.call term if callback

    term
  end

  public

  attr_reader :subject, :graph, :prefixes, :callback
  # why is this :target, :source
  alias_method :namespaces, :prefixes

  # Initialize the processor.
  #
  # @param subject  [RDF::URI] The default subject. Required.
  # @param graph    [RDF::URI] The default context. Optional.
  # @param prefixes [Hash]     Namespace/prefix mappings. Optional.
  # @param callback [#call]    A callback that expects and returns a term.
  #  Optional.
  #
  def initialize subject: nil, graph: nil, prefixes: {}, callback: nil
    # look at all of our pretty assertions
    raise ArgumentError, 'subject must be an RDF::Resource' unless
      subject.is_a? RDF::Resource
    raise ArgumentError, 'graph must be an RDF::Resource' unless
      graph.nil? or graph.is_a? RDF::Resource
    raise ArgumentError, 'prefixes must be hashable' unless
      prefixes.respond_to? :to_h
    rase ArgumentError, 'callback must be callable' unless
      callback.nil? or callback.respond_to? :call

    @subject  = subject
    @graph    = graph
    @callback = callback
    @prefixes = DEFAULT_NS.merge(prefixes.to_h.map do |k, v|
      k = k.to_s.to_sym    unless k.is_a? Symbol
      # coerce to uri
      v = RDF::URI(v.to_s) unless v.is_a? RDF::Resource
      # now coerce to vocabulary
      v = RDF::Vocabulary.new v unless v.is_a? RDF::Vocabulary
      [k, v]
    end.to_h)
  end

  # Process a hash of form input.

  # @note This operation may change the state of the processor, so
  #  while this object can be reused for multiple hashes, it is unwise
  #  to reuse it across requests.
  #
  # @param data [Hash] The data coming, e.g., from the Web form.
  # @return [RDF::Changeset] A changeset containing the results.
  #
  def process data
    raise ArgumentError, 'data must be a hash' unless data.is_a? Hash
    macros  = GENERATED.dup
    maybe   = {} # candidates
    neither = {} # discard pile

    data.each do |k, *v|
      # step 0: get the values to a homogeneous list
      k = k.to_s
      v = v.flatten.map(&:to_s)
      # step 1: pull out all the macro declarations
      if (m = /#{DECLARATION}/o.match k)
        name  = m[1].to_sym
        sigil = !!(m[2] && !m[2].empty?)
        # skip over generated macros
        next if GENERATED.key? name
        # step 1.0.1: create [content, deref flag] pairs
        (macros[name] ||= []).concat v.map { |x| [x, sigil] }
      elsif (m = /(?:^\s*\S+\s+\S+.*?$|[:\$])/.match k)
        (maybe[k] ||= []).concat v
      else
        (neither[k] ||= []).concat v
      end
    end

    # step 2: dereference all the macros (that asked to be dereferenced)
    begin
      macros = massage_macros macros
    rescue e
      # XXX we should do something more here
      raise e
    end

    # step 3: apply special control macros (which modify self)
    begin
      SPECIALS.each do |k, macro|
        instance_exec macros[k], &macro if macros[k]
      end
    rescue Exception => e
      # again this should be nicer
      raise Error.new e
    end

    # this will be our output
    patch = RDF::Changeset.new

    maybe.each do |k, v|
      # this will return an array now
      k = deref_content(k, macros).compact
      v = v.compact.map(&:strip).uniq

      # this is only this way because of macros
      k.each do |template|
        tokens = GRAMMAR.match(template) or next
        tokens = tokens.captures

        raise 'INTERNAL ERROR: Regexp captures do not match template' unless
          tokens.length == MAP.length

        # i had something much cleverer here but of course it didn't DWIW
        contents = {}
        MAP.each_index { |i| contents[MAP[i]] ||= tokens[i] }
        contents.compact!

        contents[:modifier] = (contents[:modifier] || '').chars.map do |c|
          [c, true]
        end.to_h

        if contents[:designator]
          sigil, symbol = contents[:designator].split '', 2
          symbol = resolve_term symbol if sigil == ?^
          contents[:designator] = symbol.to_s.empty? ? [sigil] : [sigil, symbol]
        else
          contents[:designator] = [contents[:modifier][?!] ? ?: : ?']
        end

        %i[term1 term2 graph].filter { |t| contents[t] }.each do |which|
          contents[which] = resolve_term contents[which]
        end

        # these are the values we actually use; ensure they are duplicated
        values = (contents[:deref] ? deref_content(v, macros) : v).dup

        g = coerce_term(contents[:graph]) || graph
        # initialize the triple
        s, p, o = nil

        # shorthand for reverse
        if reverse = !!contents[:modifier][?!]
          # literals make no sense on reverse statements
          # (XXX this is a candidate for diagnostics)
          next unless [?_, ?:].include? contents[:designator].first
          # these terms have already been resolved/coerced
          p = contents[:term1]
          o = contents[:term2] || subject
        else
          s, p = (contents[:term2] ? contents.values_at(:term1, :term2) :
                  [subject, contents[:term1]]).map { |t| resolve_term t }
        end

        # the operation depends on whether the `-` modifier is present
        op = contents[:modifier][?-] ? :delete : :insert

        # if we're deleting triples and the values contain an empty
        # string then we're deleting a wildcard, same if we `=` overwrite
        if !reverse and op == :delete && values.include?('') ||
            contents[:modifier][?=]
          # i can't remember why we don't do this in reverse, probably
          # because it is too easy to shoot yourself in the foot
          patch.delete RDF::Statement(s, p, nil, graph_name: g)

          # nuke these since it will be pointless to evaluate further
          values.clear if op == :delete
        end

        # otherwise the code is basically the same
        values.each do |x|
          # get what should be guaranteed to be an RDF term or nil
          x = coerce_term(x, *contents[:designator]) or next

          # now we assign the appropriate direction
          reverse ? s = x : o = x

          # this will be either insert or delete
          patch.send op, RDF::Statement(s, p, o, graph_name: g)
        end
      end
    end

    patch
  end

  class Error < RuntimeError; end
end
