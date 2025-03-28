require 'rdf/vocab'

RSpec.describe RDF::KV do
  let(:root) { RDF::URI('https://my.website/') }
  let(:suri) { RDF::URI('https://my.website/internet/home/page') }

  prefixes = {
    dct: RDF::Vocab::DC,
    foaf: RDF::Vocab::FOAF,
    skos: RDF::Vocab::SKOS,
    ibis: RDF::Vocabulary('https://vocab.methodandstructure.com/ibis#')
  }

  # default instance
  let(:default) { described_class.new subject: suri, prefixes: prefixes }

  # some statements
  let(:rstmt) { RDF::Statement(suri, RDF::Vocab::XHV.index, root) }
  let(:lstmt) { RDF::Statement(suri, RDF::Vocab::DC.title, 'Hi!') }
  let(:pstmt) { RDF::Statement(suri, RDF::Vocab::DC.title, nil) }

  it 'has a version number' do
    expect(RDF::KV::VERSION).not_to be nil
  end

  context 'basic operation' do

    it 'should add simple statements to the insert side' do
      this = described_class.new subject: suri,
        prefixes: { xhv: RDF::Vocab::XHV }

      patch = this.process({
        'xhv:index :' => '/',
        RDF::Vocab::DC.title.to_s => 'Hi!',
      })

      expect(patch.inserts).to include(rstmt)
      expect(patch.inserts).to include(lstmt)
    end

    it 'should add simple statements to the delete side' do
      this = described_class.new subject: suri,
        prefixes: { dct: RDF::Vocab::DC }

      patch = this.process({ '- dct:title' => 'Hi!' })
      expect(patch.deletes).to include(lstmt)
    end

    it 'should add wildcard statements to the delete side' do
      this = described_class.new subject: suri,
        prefixes: { dct: RDF::Vocab::DC }

      patch = this.process({ '- dct:title' => '' })
      expect(patch.deletes).to include(pstmt)
    end
  end

  context 'macros' do
    it 'handles special macros' do
      lol = RDF::URI('http://foo.com/lol')
      uu  = RDF::URI('urn:uuid:7c04f768-e23f-488b-9357-de15e7e1ac70')
      ns  = RDF::Vocabulary.new('http://foo.bar/prefix')

      patch = default.process({
        '$ GRAPH'   => lol.to_s,
        '$ SUBJECT' => uu.to_s,
        '$ PREFIX'  => "foo: #{ns.to_s}",
      })

      expect(default.graph).to eq(lol)
      expect(default.subject).to eq(uu)
      expect(default.prefixes[:foo].to_s).to eq(ns.to_s)
    end

    it 'can set macros' do
      # add the namespace to the instance
      default.prefixes[:dct] = RDF::Vocab::DC

      patch = default.process({ '$ lol' => 'Hi!', 'dct:title $' => '$lol' })

      expect(patch.inserts).to include(lstmt)
    end

    it 'can generate values' do
      default.prefixes[:dct] = RDF::Vocab::DC
      patch = default.process({ 'dct:audience : $' => '$NEW_UUID_URN' })

      expect(patch.inserts.first.object).to be_a(RDF::URI)
    end

    it 'can set macros to generated values' do
      patch = default.process({
        '$ PREFIX' => 'dct: http://purl.org/dc/terms/',
        '$ lol $' => '$NEW_UUID_URN',
        'dct:creator : $' => '$lol',
      })
      # warn patch.inserts.first
      expect(patch.inserts.first.object).to be_a(RDF::URI)
    end

    it 'can set macros to multiple values' do
      # add the namespace to the instance
      default.prefixes[:dct] = RDF::Vocab::DC

      patch = default.process({
        '$ lol' => ['Hi!', 'lolwut'],
        'dct:title $' => '$lol'
      })
      lolwut = RDF::Statement(suri, RDF::Vocab::DC.title, 'lolwut')
      expect(patch.inserts).to include(lolwut)
    end

    it 'generates time stamps' do
      patch = default.process({
        'dct:created ^xsd:dateTime $' => '$NEW_TIME_UTC'
      })
      expect(patch.inserts.first.object).to be_a(RDF::Literal)
      expect(patch.inserts.first.object.object).to be_a(DateTime)
    end

    it "shouldn't be weird about this" do
      scheme = RDF::URI('http://localhost:10101/7b59bc41-a915-428a-9d2e-d62b123d1905')
      post = {
        '$ SUBJECT $' => '$NEW_UUID_URN',
        'ibis:suggested-by :' => 'http://localhost:10101/45aa5cec-60dd-4091-af9d-3fc25722db38',
        'dct:created ^xsd:dateTime $' => '$NEW_TIME_UTC',
        'dct:creator :' => 'http://localhost:10101/person/dorian-taylor#me',
        'skos:inScheme :' => scheme.to_s,
        '$ type' => 'ibis:Issue',
        '= rdf:value $' => '$label',
        '= rdf:type : $' => '$type',
        '$ label' => 'grrr come on',
      }
      g = RDF::Repository.new
      patch = default.process post
      patch.apply g
      huh = g.query([nil, RDF::Vocab::SKOS.inScheme, nil]).objects.first
      expect(huh).to eq(scheme)

    end

  end
end
