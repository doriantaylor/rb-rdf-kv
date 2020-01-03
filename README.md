# RDF::KV — Turn Key-Value Pairs into an RDF::Changeset

This module is an implementation of the
[RDF-KV](https://doriantaylor.com/rdf-kv) protocol. This protocol
defines a method for embedding instructions for constructing a
[changeset](https://rubydoc.info/gems/rdf/RDF/Changeset) from ordinary
key-value pairs.

```ruby
# initialize the processor
kv = RDF::KV.new subject: my_url, graph: graph_url

# use it to generate a changeset, e.g. from web form POST data
cs = kv.process rack.POST

# now apply it to your RDF::Repository
cs.apply repo
```

## Documentation

API documentation, for what it's worth at the moment, can be found [in
the usual place](https://rubydoc.info/github/doriantaylor/rb-rdf-kv/master).

## Installation

You know how to do this:

    $ gem install rdf-kv

Or, [download it off rubygems.org](https://rubygems.org/gems/rdf-kv).

## Contributing

Bug reports and pull requests are welcome at
[the GitHub repository](https://github.com/doriantaylor/rb-rdf-kv).

## Copyright & License

©2019 [Dorian Taylor](https://doriantaylor.com/)

This software is provided under
the [Apache License, 2.0](https://www.apache.org/licenses/LICENSE-2.0).
