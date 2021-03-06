# coding: utf-8
$:.unshift "."
require 'spec_helper'
require 'rdf/xsd'
require 'rdf/spec/reader'

# Add for testing
class JSON::LD::Context
  # Retrieve type mappings
  def coercions
    term_definitions.inject({}) do |memo, (t,td)|
      memo[t] = td.type_mapping
      memo
    end
  end

  def containers
    term_definitions.inject({}) do |memo, (t,td)|
      memo[t] = td.container_mapping
      memo
    end
  end
end

describe JSON::LD::Context do
  before(:each) {
    @debug = []
  }
  let(:context) {JSON::LD::Context.new(:debug => @debug, :validate => true)}
  let(:remote_doc) do
    JSON::LD::API::RemoteDocument.new("http://example.com/context", %q({
      "@context": {
        "xsd": "http://www.w3.org/2001/XMLSchema#",
        "name": "http://xmlns.com/foaf/0.1/name",
        "homepage": {"@id": "http://xmlns.com/foaf/0.1/homepage", "@type": "@id"},
        "avatar": {"@id": "http://xmlns.com/foaf/0.1/avatar", "@type": "@id"}
      }
    }))
  end
  subject {context}

  describe "#parse" do
    context "remote" do

      it "retrieves and parses a remote context document" do
        JSON::LD::API.stub(:documentLoader).with("http://example.com/context").and_yield(remote_doc)
        ec = subject.parse("http://example.com/context")
        ec.provided_context.should produce("http://example.com/context", @debug)
      end

      it "fails given a missing remote @context" do
        JSON::LD::API.stub(:documentLoader).with("http://example.com/context").and_raise(IOError)
        lambda {subject.parse("http://example.com/context")}.should raise_error(JSON::LD::JsonLdError::LoadingRemoteContextFailed, %r{http://example.com/context})
      end

      it "creates mappings" do
        JSON::LD::API.stub(:documentLoader).with("http://example.com/context").and_yield(remote_doc)
        ec = subject.parse("http://example.com/context")
        ec.mappings.should produce({
          "xsd"      => "http://www.w3.org/2001/XMLSchema#",
          "name"     => "http://xmlns.com/foaf/0.1/name",
          "homepage" => "http://xmlns.com/foaf/0.1/homepage",
          "avatar"   => "http://xmlns.com/foaf/0.1/avatar"
        }, @debug)
      end
      
      it "notes non-existing @context" do
        lambda {subject.parse(StringIO.new("{}"))}.should raise_error
      end
      
      it "parses a referenced context at a relative URI" do
        rd1 = JSON::LD::API::RemoteDocument.new("http://example.com/c1", %({"@context": "context"}))
        JSON::LD::API.stub(:documentLoader).with("http://example.com/c1").and_yield(rd1)
        JSON::LD::API.stub(:documentLoader).with("http://example.com/context").and_yield(remote_doc)
        ec = subject.parse("http://example.com/c1")
        ec.mappings.should produce({
          "xsd"      => "http://www.w3.org/2001/XMLSchema#",
          "name"     => "http://xmlns.com/foaf/0.1/name",
          "homepage" => "http://xmlns.com/foaf/0.1/homepage",
          "avatar"   => "http://xmlns.com/foaf/0.1/avatar"
        }, @debug)
      end
    end

    context "Array" do
      before(:all) do
        @ctx = [
          {"foo" => "http://example.com/foo"},
          {"bar" => "foo"}
        ]
      end

      it "merges definitions from each context" do
        ec = subject.parse(@ctx)
        ec.mappings.should produce({
          "foo" => "http://example.com/foo",
          "bar" => "http://example.com/foo"
        }, @debug)
      end
    end

    context "Hash" do
      it "extracts @language" do
        subject.parse({
          "@language" => "en"
        }).default_language.should produce("en", @debug)
      end

      it "extracts @vocab" do
        subject.parse({
          "@vocab" => "http://schema.org/"
        }).vocab.should produce("http://schema.org/", @debug)
      end

      it "maps term with IRI value" do
        subject.parse({
          "foo" => "http://example.com/"
        }).mappings.should produce({
          "foo" => "http://example.com/"
        }, @debug)
      end

      it "maps term with @id" do
        subject.parse({
          "foo" => {"@id" => "http://example.com/"}
        }).mappings.should produce({
          "foo" => "http://example.com/"
        }, @debug)
      end

      it "associates @list container mapping with predicate" do
        subject.parse({
          "foo" => {"@id" => "http://example.com/", "@container" => "@list"}
        }).containers.should produce({
          "foo" => '@list'
        }, @debug)
      end

      it "associates @set container mapping with predicate" do
        subject.parse({
          "foo" => {"@id" => "http://example.com/", "@container" => "@set"}
        }).containers.should produce({
          "foo" => '@set'
        }, @debug)
      end

      it "associates @id container mapping with predicate" do
        subject.parse({
          "foo" => {"@id" => "http://example.com/", "@type" => "@id"}
        }).coercions.should produce({
          "foo" => "@id"
        }, @debug)
      end

      it "associates type mapping with predicate" do
        subject.parse({
          "foo" => {"@id" => "http://example.com/", "@type" => RDF::XSD.string.to_s}
        }).coercions.should produce({
          "foo" => RDF::XSD.string.to_s
        }, @debug)
      end

      it "associates language mapping with predicate" do
        subject.parse({
          "foo" => {"@id" => "http://example.com/", "@language" => "en"}
        }).languages.should produce({
          "foo" => "en"
        }, @debug)
      end

      it "expands chains of term definition/use with string values" do
        subject.parse({
          "foo" => "bar",
          "bar" => "baz",
          "baz" => "http://example.com/"
        }).mappings.should produce({
          "foo" => "http://example.com/",
          "bar" => "http://example.com/",
          "baz" => "http://example.com/"
        }, @debug)
      end

      it "expands terms using @vocab" do
        subject.parse({
          "foo" => "bar",
          "@vocab" => "http://example.com/"
        }).mappings.should produce({
          "foo" => "http://example.com/bar"
        }, @debug)
      end

      context "with null" do
        it "removes @language if set to null" do
          subject.parse([
            {
              "@language" => "en"
            },
            {
              "@language" => nil
            }
          ]).default_language.should produce(nil, @debug)
        end

        it "removes @vocab if set to null" do
          subject.parse([
            {
              "@vocab" => "http://schema.org/"
            },
            {
              "@vocab" => nil
            }
          ]).vocab.should produce(nil, @debug)
        end

        it "removes term if set to null with @vocab" do
          subject.parse([
            {
              "@vocab" => "http://schema.org/",
              "term" => nil
            }
          ]).mappings.should produce({"term" => nil}, @debug)
        end

        it "loads initial context" do
          init_ec = JSON::LD::Context.new
          nil_ec = subject.parse(nil)
          nil_ec.default_language.should == init_ec.default_language
          nil_ec.languages.should == init_ec.languages
          nil_ec.mappings.should == init_ec.mappings
          nil_ec.coercions.should == init_ec.coercions
          nil_ec.containers.should == init_ec.containers
        end
        
        it "removes a term definition" do
          subject.parse({"name" => nil}).mapping("name").should be_nil
        end
      end
    end

    describe "Syntax Errors" do
      {
        "malformed JSON" => StringIO.new(%q({"@context": {"foo" "http://malformed/"})),
        "no @id, @type, or @container" => {"foo" => {}},
        "value as array" => {"foo" => []},
        "@id as object" => {"foo" => {"@id" => {}}},
        "@id as array of object" => {"foo" => {"@id" => [{}]}},
        "@id as array of null" => {"foo" => {"@id" => [nil]}},
        "@type as object" => {"foo" => {"@type" => {}}},
        "@type as array" => {"foo" => {"@type" => []}},
        "@type as @list" => {"foo" => {"@type" => "@list"}},
        "@type as @list" => {"foo" => {"@type" => "@set"}},
        "@container as object" => {"foo" => {"@container" => {}}},
        "@container as array" => {"foo" => {"@container" => []}},
        "@container as string" => {"foo" => {"@container" => "true"}},
        "@language as @id" => {"@language" => {"@id" => "http://example.com/"}},
        "@vocab as @id" => {"@vocab" => {"@id" => "http://example.com/"}},
      }.each do |title, context|
        it title do
          lambda {
            ec = subject.parse(context)
            ec.serialize.should produce({}, @debug)
          }.should raise_error(JSON::LD::JsonLdError)
        end
      end
      
      (JSON::LD::KEYWORDS - %w(@base @language @vocab)).each do |kw|
        it "does not redefine #{kw} as a string" do
          lambda {
            ec = subject.parse({kw => "http://example.com/"})
            ec.serialize.should produce({}, @debug)
          }.should raise_error(JSON::LD::JsonLdError)
        end

        it "does not redefine #{kw} with an @id" do
          lambda {
            ec = subject.parse({kw => {"@id" => "http://example.com/"}})
            ec.serialize.should produce({}, @debug)
          }.should raise_error(JSON::LD::JsonLdError)
        end
      end
    end
  end

  describe "#serialize" do
    it "context document" do
      JSON::LD::API.stub(:documentLoader).with("http://example.com/context").and_yield(remote_doc)
      ec = subject.parse("http://example.com/context")
      ec.serialize.should produce({
        "@context" => "http://example.com/context"
      }, @debug)
    end

    it "context hash" do
      ctx = {"foo" => "http://example.com/"}

      ec = subject.parse(ctx)
      ec.serialize.should produce({
        "@context" => ctx
      }, @debug)
    end

    it "@language" do
      subject.default_language = "en"
      subject.serialize.should produce({
        "@context" => {
          "@language" => "en"
        }
      }, @debug)
    end

    it "@vocab" do
      subject.vocab = "http://example.com/"
      subject.serialize.should produce({
        "@context" => {
          "@vocab" => "http://example.com/"
        }
      }, @debug)
    end

    it "term mappings" do
      subject.
        parse({'foo' => "http://example.com/"}).send(:clear_provided_context).
        serialize.should produce({
        "@context" => {
          "foo" => "http://example.com/"
        }
      }, @debug)
    end

    it "@type with dependent prefixes in a single context" do
      subject.parse({
        'xsd' => "http://www.w3.org/2001/XMLSchema#",
        'homepage' => {'@id' => RDF::FOAF.homepage.to_s, '@type' => '@id'}
      }).
      send(:clear_provided_context).
      serialize.should produce({
        "@context" => {
          "xsd" => RDF::XSD.to_uri,
          "homepage" => {"@id" => RDF::FOAF.homepage.to_s, "@type" => "@id"}
        }
      }, @debug)
    end

    it "@list with @id definition in a single context" do
      subject.parse({
        'knows' => {'@id' => RDF::FOAF.knows.to_s, '@container' => '@list'}
      }).
      send(:clear_provided_context).
      serialize.should produce({
        "@context" => {
          "knows" => {"@id" => RDF::FOAF.knows.to_s, "@container" => "@list"}
        }
      }, @debug)
    end

    it "@set with @id definition in a single context" do
      subject.parse({
        "knows" => {"@id" => RDF::FOAF.knows.to_s, "@container" => "@set"}
      }).
      send(:clear_provided_context).
      serialize.should produce({
        "@context" => {
          "knows" => {"@id" => RDF::FOAF.knows.to_s, "@container" => "@set"}
        }
      }, @debug)
    end

    it "@language with @id definition in a single context" do
      subject.parse({
        "name" => {"@id" => RDF::FOAF.name.to_s, "@language" => "en"}
      }).
      send(:clear_provided_context).
      serialize.should produce({
        "@context" => {
          "name" => {"@id" => RDF::FOAF.name.to_s, "@language" => "en"}
        }
      }, @debug)
    end

    it "@language with @id definition in a single context and equivalent default" do
      subject.parse({
        "@language" => 'en',
        "name" => {"@id" => RDF::FOAF.name.to_s, "@language" => 'en'}
      }).
      send(:clear_provided_context).
      serialize.should produce({
        "@context" => {
          "@language" => 'en',
          "name" => {"@id" => RDF::FOAF.name.to_s, "@language" => 'en'}
        }
      }, @debug)
    end

    it "@language with @id definition in a single context and different default" do
      subject.parse({
        "@language" => 'en',
        "name" => {"@id" => RDF::FOAF.name.to_s, "@language" => "de"}
      }).
      send(:clear_provided_context).
      serialize.should produce({
        "@context" => {
          "@language" => 'en',
          "name" => {"@id" => RDF::FOAF.name.to_s, "@language" => "de"}
        }
      }, @debug)
    end

    it "null @language with @id definition in a single context and default" do
      subject.parse({
        "@language" => 'en',
        "name" => {"@id" => RDF::FOAF.name.to_s, "@language" => nil}
      }).
      send(:clear_provided_context).
      serialize.should produce({
        "@context" => {
          "@language" => 'en',
          "name" => {"@id" => RDF::FOAF.name.to_s, "@language" => nil}
        }
      }, @debug)
    end

    it "prefix with @type and @list" do
      subject.parse({
        "knows" => {"@id" => RDF::FOAF.knows.to_s, "@type" => "@id", "@container" => "@list"}
      }).
      send(:clear_provided_context).
      serialize.should produce({
        "@context" => {
          "knows" => {"@id" => RDF::FOAF.knows.to_s, "@type" => "@id", "@container" => "@list"}
        }
      }, @debug)
    end

    it "prefix with @type and @set" do
      subject.parse({
        "knows" => {"@id" => RDF::FOAF.knows.to_s, "@type" => "@id", "@container" => "@set"}
      }).
      send(:clear_provided_context).
      serialize.should produce({
        "@context" => {
          "knows" => {"@id" => RDF::FOAF.knows.to_s, "@type" => "@id", "@container" => "@set"}
        }
      }, @debug)
    end

    it "CURIE with @type" do
      subject.parse({
        "foaf" => RDF::FOAF.to_uri.to_s,
        "foaf:knows" => {
          "@id" => RDF::FOAF.knows.to_s,
          "@container" => "@list"
        }
      }).
      send(:clear_provided_context).
      serialize.should produce({
        "@context" => {
          "foaf" => RDF::FOAF.to_uri.to_s,
          "foaf:knows" => {
            "@container" => "@list"
          }
        }
      }, @debug)
    end

    it "does not use aliased @id in key position" do
      subject.parse({
        "id" => "@id",
        "knows" => {"@id" => RDF::FOAF.knows.to_s, "@container" => "@list"}
      }).
      send(:clear_provided_context).
      serialize.should produce({
        "@context" => {
          "id" => "@id",
          "knows" => {"@id" => RDF::FOAF.knows.to_s, "@container" => "@list"}
        }
      }, @debug)
    end

    it "does not use aliased @id in value position" do
      subject.parse({
        "foaf" => RDF::FOAF.to_uri.to_s,
        "id" => "@id",
        "foaf:homepage" => {
          "@id" => RDF::FOAF.homepage.to_s,
          "@type" => "@id"
        }
      }).
      send(:clear_provided_context).
      serialize.should produce({
        "@context" => {
          "foaf" => RDF::FOAF.to_uri.to_s,
          "id" => "@id",
          "foaf:homepage" => {
            "@type" => "@id"
          }
        }
      }, @debug)
    end

    it "does not use aliased @type" do
      subject.parse({
        "foaf" => RDF::FOAF.to_uri.to_s,
        "type" => "@type",
        "foaf:homepage" => {"@type" => "@id"}
      }).
      send(:clear_provided_context).
      serialize.should produce({
        "@context" => {
          "foaf" => RDF::FOAF.to_uri.to_s,
          "type" => "@type",
          "foaf:homepage" => {"@type" => "@id"}
        }
      }, @debug)
    end

    it "does not use aliased @container" do
      subject.parse({
        "container" => "@container",
        "knows" => {"@id" => RDF::FOAF.knows.to_s, "@container" => "@list"}
      }).
      send(:clear_provided_context).
      serialize.should produce({
        "@context" => {
          "container" => "@container",
          "knows" => {"@id" => RDF::FOAF.knows.to_s, "@container" => "@list"}
        }
      }, @debug)
    end

    it "compacts IRIs to CURIEs" do
      subject.parse({
        "ex" => 'http://example.org/',
        "term" => {"@id" => "ex:term", "@type" => "ex:datatype"}
      }).
      send(:clear_provided_context).
      serialize.should produce({
        "@context" => {
          "ex" => 'http://example.org/',
          "term" => {"@id" => "ex:term", "@type" => "ex:datatype"}
        }
      }, @debug)
    end

    it "compacts IRIs using @vocab" do
      subject.parse({
        "@vocab" => 'http://example.org/',
        "term" => {"@id" => "http://example.org/term", "@type" => "datatype"}
      }).
      send(:clear_provided_context).
      serialize.should produce({
        "@context" => {
          "@vocab" => 'http://example.org/',
          "term" => {"@id" => "http://example.org/term", "@type" => "datatype"}
        }
      }, @debug)
    end

    context "extra keys or values" do
      {
        "extra key" => {
          :input => {"foo" => {"@id" => "http://example.com/foo", "@baz" => "foobar"}},
          :result => {"@context" => {"foo" => "http://example.com/foo"}}
        }
      }.each do |title, params|
        it title do
          ec = subject.parse(params[:input])
          ec.serialize.should produce(params[:result], @debug)
        end
      end
    end

  end

  describe "#expand_iri" do
    subject {
      context.parse({
        '@base' => 'http://base/',
        '@vocab' => 'http://vocab/',
        'ex' => 'http://example.org/',
        '' => 'http://empty/',
        '_' => 'http://underscore/'
      })
    }

    it "bnode" do
      subject.expand_iri("_:a").should be_a(RDF::Node)
    end

    context "keywords" do
      %w(id type).each do |kw|
        it "expands #{kw} to @#{kw}" do
          subject.set_mapping(kw, "@#{kw}")
          subject.expand_iri(kw, :vocab => true).should produce("@#{kw}", @debug)
        end
      end
    end

    context "relative IRI" do
      context "with no options" do
        {
          "absolute IRI" =>  ["http://example.org/", RDF::URI("http://example.org/")],
          "term" =>          ["ex",                  RDF::URI("ex")],
          "prefix:suffix" => ["ex:suffix",           RDF::URI("http://example.org/suffix")],
          "keyword" =>       ["@type",               "@type"],
          "empty" =>         [":suffix",             RDF::URI("http://empty/suffix")],
          "unmapped" =>      ["foo",                 RDF::URI("foo")],
          "empty term" =>    ["",                    RDF::URI("")],
          "another abs IRI"=>["ex://foo",            RDF::URI("ex://foo")],
          "absolute IRI looking like a curie" =>
                             ["foo:bar",             RDF::URI("foo:bar")],
          "bnode" =>         ["_:t0",                RDF::Node("t0")],
          "_" =>             ["_",                   RDF::URI("_")],
        }.each do |title, (input, result)|
          it title do
            subject.expand_iri(input).should produce(result, @debug)
          end
        end
      end

      context "with base IRI" do
        {
          "absolute IRI" =>  ["http://example.org/", RDF::URI("http://example.org/")],
          "term" =>          ["ex",                  RDF::URI("http://base/ex")],
          "prefix:suffix" => ["ex:suffix",           RDF::URI("http://example.org/suffix")],
          "keyword" =>       ["@type",               "@type"],
          "empty" =>         [":suffix",             RDF::URI("http://empty/suffix")],
          "unmapped" =>      ["foo",                 RDF::URI("http://base/foo")],
          "empty term" =>    ["",                    RDF::URI("http://base/")],
          "another abs IRI"=>["ex://foo",            RDF::URI("ex://foo")],
          "absolute IRI looking like a curie" =>
                             ["foo:bar",             RDF::URI("foo:bar")],
          "bnode" =>         ["_:t0",                RDF::Node("t0")],
          "_" =>             ["_",                   RDF::URI("http://base/_")],
        }.each do |title, (input, result)|
          it title do
            subject.expand_iri(input, :documentRelative => true).should produce(result, @debug)
          end
        end
      end
    
      context "@vocab" do
        {
          "absolute IRI" =>  ["http://example.org/", RDF::URI("http://example.org/")],
          "term" =>          ["ex",                  RDF::URI("http://example.org/")],
          "prefix:suffix" => ["ex:suffix",           RDF::URI("http://example.org/suffix")],
          "keyword" =>       ["@type",               "@type"],
          "empty" =>         [":suffix",             RDF::URI("http://empty/suffix")],
          "unmapped" =>      ["foo",                 RDF::URI("http://vocab/foo")],
          "empty term" =>    ["",                    RDF::URI("http://empty/")],
          "another abs IRI"=>["ex://foo",            RDF::URI("ex://foo")],
          "absolute IRI looking like a curie" =>
                             ["foo:bar",             RDF::URI("foo:bar")],
          "bnode" =>         ["_:t0",                RDF::Node("t0")],
          "_" =>             ["_",                   RDF::URI("http://underscore/")],
        }.each do |title, (input, result)|
          it title do
            subject.expand_iri(input, :vocab => true).should produce(result, @debug)
          end
        end
      end
    end
  end

  describe "#compact_iri" do
    subject {
      c = context.parse({
        '@base' => 'http://base/',
        "xsd"   => "http://www.w3.org/2001/XMLSchema#",
        'ex'    => 'http://example.org/',
        ''      => 'http://empty/',
        '_'     => 'http://underscore/',
        'rex'   => {'@reverse' => "ex"},
        'lex'   => {'@id' => 'ex', '@language' => 'en'},
        'tex'   => {'@id' => 'ex', '@type' => 'xsd:string'}
      })
      @debug.clear
      c
    }

    {
      "nil" => [nil, nil],
      "absolute IRI"  => ["http://example.com/", "http://example.com/"],
      "prefix:suffix" => ["ex:suffix",           "http://example.org/suffix"],
      "keyword"       => ["@type",               "@type"],
      "empty"         => [":suffix",             "http://empty/suffix"],
      "unmapped"      => ["foo",                 "foo"],
      "bnode"         => ["_:a",                 RDF::Node("a")],
      "relative"      => ["foo/bar",             "http://base/foo/bar"]
    }.each do |title, (result, input)|
      it title do
        subject.compact_iri(input).should produce(result, @debug)
      end
    end

    context "with :vocab option" do
      {
        "absolute IRI"  => ["http://example.com/", "http://example.com/"],
        "prefix:suffix" => ["ex:suffix",           "http://example.org/suffix"],
        "keyword"       => ["@type",               "@type"],
        "empty"         => [":suffix",             "http://empty/suffix"],
        "unmapped"      => ["foo",                 "foo"],
        "bnode"         => ["_:a",                 RDF::Node("a")],
        "relative"      => ["http://base/foo/bar", "http://base/foo/bar"]
      }.each do |title, (result, input)|
        it title do
          subject.compact_iri(input, :vocab => true).should produce(result, @debug)
        end
      end
    end

    context "with @vocab" do
      before(:each) { subject.vocab = "http://example.org/"}

      {
        "absolute IRI"  => ["http://example.com/", "http://example.com/"],
        "prefix:suffix" => ["suffix",              "http://example.org/suffix"],
        "keyword"       => ["@type",               "@type"],
        "empty"         => [":suffix",             "http://empty/suffix"],
        "unmapped"      => ["foo",                 "foo"],
        "bnode"         => ["_:a",                 RDF::Node("a")],
        "relative"      => ["http://base/foo/bar", "http://base/foo/bar"]
      }.each do |title, (result, input)|
        it title do
          subject.compact_iri(input, :vocab => true).should produce(result, @debug)
        end
      end

      it "does not use @vocab if it would collide with a term" do
        subject.set_mapping("name", "http://xmlns.com/foaf/0.1/name")
        subject.set_mapping("ex", nil)
        subject.compact_iri("http://example.org/name", :position => :predicate).
          should produce("lex:name", @debug)
      end
    end

    context "with value" do
      let(:ctx) do
        c = subject.parse({
          "xsd" => RDF::XSD.to_s,
          "plain" => "http://example.com/plain",
          "lang" => {"@id" => "http://example.com/lang", "@language" => "en"},
          "bool" => {"@id" => "http://example.com/bool", "@type" => "xsd:boolean"},
          "integer" => {"@id" => "http://example.com/integer", "@type" => "xsd:integer"},
          "double" => {"@id" => "http://example.com/double", "@type" => "xsd:double"},
          "date" => {"@id" => "http://example.com/date", "@type" => "xsd:date"},
          "id" => {"@id" => "http://example.com/id", "@type" => "@id"},
          "listplain" => {"@id" => "http://example.com/plain", "@container" => "@list"},
          "listlang" => {"@id" => "http://example.com/lang", "@language" => "en", "@container" => "@list"},
          "listbool" => {"@id" => "http://example.com/bool", "@type" => "xsd:boolean", "@container" => "@list"},
          "listinteger" => {"@id" => "http://example.com/integer", "@type" => "xsd:integer", "@container" => "@list"},
          "listdouble" => {"@id" => "http://example.com/double", "@type" => "xsd:double", "@container" => "@list"},
          "listdate" => {"@id" => "http://example.com/date", "@type" => "xsd:date", "@container" => "@list"},
          "listid" => {"@id" => "http://example.com/id", "@type" => "@id", "@container" => "@list"},
          "setplain" => {"@id" => "http://example.com/plain", "@container" => "@set"},
          "setlang" => {"@id" => "http://example.com/lang", "@language" => "en", "@container" => "@set"},
          "setbool" => {"@id" => "http://example.com/bool", "@type" => "xsd:boolean", "@container" => "@set"},
          "setinteger" => {"@id" => "http://example.com/integer", "@type" => "xsd:integer", "@container" => "@set"},
          "setdouble" => {"@id" => "http://example.com/double", "@type" => "xsd:double", "@container" => "@set"},
          "setdate" => {"@id" => "http://example.com/date", "@type" => "xsd:date", "@container" => "@set"},
          "setid" => {"@id" => "http://example.com/id", "@type" => "@id", "@container" => "@set"},
          "langmap" => {"@id" => "http://example.com/langmap", "@container" => "@language"},
        })
        @debug.clear
        c
      end

      {
        "langmap" => [{"@value" => "en", "@language" => "en"}],
        #"plain" => [{"@value" => "foo"}],
        "setplain" => [{"@value" => "foo", "@language" => "pl"}]
      }.each do |prop, values|
        context "uses #{prop}" do
          values.each do |value|
            it "for #{value.inspect}" do
              ctx.compact_iri("http://example.com/#{prop.sub('set', '')}", :value => value, :vocab => true).should produce(prop, @debug)
            end
          end
        end
      end

      context "for @list" do
        {
          "listplain"   => [
            [{"@value" => "foo"}],
            [{"@value" => "foo"}, {"@value" => "bar"}, {"@value" => "baz"}],
            [{"@value" => "foo"}, {"@value" => "bar"}, {"@value" => 1}],
            [{"@value" => "foo"}, {"@value" => "bar"}, {"@value" => 1.1}],
            [{"@value" => "foo"}, {"@value" => "bar"}, {"@value" => true}],
            [{"@value" => "foo"}, {"@value" => "bar"}, {"@value" => 1}],
            [{"@value" => "de", "@language" => "de"}, {"@value" => "jp", "@language" => "jp"}],
            [{"@value" => true}], [{"@value" => false}], 
            [[{"@value" => 1}], [{"@value" => 1.1}], 
          ],
          "listlang" => [[{"@value" => "en", "@language" => "en"}]],
          "listbool" => [[{"@value" => "true", "@type" => RDF::XSD.boolean.to_s}]],
          "listinteger" => [{"@value" => "1", "@type" => RDF::XSD.integer.to_s}]],
          "listdouble" => [[{"@value" => "1", "@type" => RDF::XSD.double.to_s}]],
          "listdate" => [[{"@value" => "2012-04-17", "@type" => RDF::XSD.date.to_s}]],
        }.each do |prop, values|
          context "uses #{prop}" do
            values.each do |value|
              it "for #{{"@list" => value}.inspect}" do
                ctx.compact_iri("http://example.com/#{prop.sub('list', '')}", :value => {"@list" => value}, :vocab => true).should produce(prop, @debug)
              end
            end
          end
        end
      end
    end

    context "compact-0018" do
      let(:ctx) do
        subject.parse(JSON.parse %({
          "id1": "http://example.com/id1",
          "type1": "http://example.com/t1",
          "type2": "http://example.com/t2",
          "@language": "de",
          "term": {
            "@id": "http://example.com/term"
          },
          "term1": {
            "@id": "http://example.com/term",
            "@container": "@list"
          },
          "term2": {
            "@id": "http://example.com/term",
            "@container": "@list",
            "@language": "en"
          },
          "term3": {
            "@id": "http://example.com/term",
            "@container": "@list",
            "@language": null
          },
          "term4": {
            "@id": "http://example.com/term",
            "@container": "@list",
            "@type": "type1"
          },
          "term5": {
            "@id": "http://example.com/term",
            "@container": "@list",
            "@type": "type2"
          }
        }))
      end

      {
        "term" => [
          '{ "@value": "v0.1", "@language": "de" }',
          '{ "@value": "v0.2", "@language": "en" }',
          '{ "@value": "v0.3"}',
          '{ "@value": 4}',
          '{ "@value": true}',
          '{ "@value": false}'
        ],
        "term1" => %q({
          "@list": [
            { "@value": "v1.1", "@language": "de" },
            { "@value": "v1.2", "@language": "en" },
            { "@value": "v1.3"},
            { "@value": 14},
            { "@value": true},
            { "@value": false}
          ]
        }),
        "term2" => %q({
          "@list": [
            { "@value": "v2.1", "@language": "en" },
            { "@value": "v2.2", "@language": "en" },
            { "@value": "v2.3", "@language": "en" },
            { "@value": "v2.4", "@language": "en" },
            { "@value": "v2.5", "@language": "en" },
            { "@value": "v2.6", "@language": "en" }
          ]
        }),
        "term3" => %q({
          "@list": [
            { "@value": "v3.1"},
            { "@value": "v3.2"},
            { "@value": "v3.3"},
            { "@value": "v3.4"},
            { "@value": "v3.5"},
            { "@value": "v3.6"}
          ]
        }),
        "term4" => %q({
          "@list": [
            { "@value": "v4.1", "@type": "http://example.com/t1" },
            { "@value": "v4.2", "@type": "http://example.com/t1" },
            { "@value": "v4.3", "@type": "http://example.com/t1" },
            { "@value": "v4.4", "@type": "http://example.com/t1" },
            { "@value": "v4.5", "@type": "http://example.com/t1" },
            { "@value": "v4.6", "@type": "http://example.com/t1" }
          ]
        }),
        "term5" => %q({
          "@list": [
            { "@value": "v5.1", "@type": "http://example.com/t2" },
            { "@value": "v5.2", "@type": "http://example.com/t2" },
            { "@value": "v5.3", "@type": "http://example.com/t2" },
            { "@value": "v5.4", "@type": "http://example.com/t2" },
            { "@value": "v5.5", "@type": "http://example.com/t2" },
            { "@value": "v5.6", "@type": "http://example.com/t2" }
          ]
        }),
      }.each do |term, value|
        [value].flatten.each do |v|
          it "Uses #{term} for #{v}" do
            ctx.compact_iri("http://example.com/term", :value => JSON.parse(v), :vocab => true).
              should produce(term, @debug)
          end
        end
      end
    end

    context "compact-0020" do
      let(:ctx) do
        subject.parse({
          "ex" => "http://example.org/ns#",
          "ex:property" => {"@container" => "@list"}
        })
      end
      it "Compact @id that is a property IRI when @container is @list" do
        ctx.compact_iri("http://example.org/ns#property", :position => :subject).
          should produce("ex:property", @debug)
      end
    end

    context "compact-0041" do
      let(:ctx) do
        subject.parse({"name" => {"@id" => "http://example.com/property", "@container" => "@list"}})
      end
      it "Does not use @list with @index" do
        ctx.compact_iri("http://example.com/property", :value => {
          "@list" => ["one item"],
          "@index" => "an annotation"
        }).should produce("http://example.com/property", @debug)
      end
    end
  end

  describe "#expand_value" do
    subject {
      ctx = context.parse({
        "dc" => RDF::DC.to_uri.to_s,
        "ex" => "http://example.org/",
        "foaf" => RDF::FOAF.to_uri.to_s,
        "xsd" => "http://www.w3.org/2001/XMLSchema#",
        "foaf:age" => {"@type" => "xsd:integer"},
        "foaf:knows" => {"@type" => "@id"},
        "dc:created" => {"@type" => "xsd:date"},
        "ex:integer" => {"@type" => "xsd:integer"},
        "ex:double" => {"@type" => "xsd:double"},
        "ex:boolean" => {"@type" => "xsd:boolean"},
      })
      @debug.clear
      ctx
    }

    %w(boolean integer string dateTime date time).each do |dt|
      it "expands datatype xsd:#{dt}" do
        subject.expand_value("foo", RDF::XSD[dt]).should produce({"@id" => "http://www.w3.org/2001/XMLSchema##{dt}"}, @debug)
      end
    end

    {
      "absolute IRI" =>   ["foaf:knows",  "http://example.com/",  {"@id" => "http://example.com/"}],
      "term" =>           ["foaf:knows",  "ex",                   {"@id" => "ex"}],
      "prefix:suffix" =>  ["foaf:knows",  "ex:suffix",            {"@id" => "http://example.org/suffix"}],
      "no IRI" =>         ["foo",         "http://example.com/",  {"@value" => "http://example.com/"}],
      "no term" =>        ["foo",         "ex",                   {"@value" => "ex"}],
      "no prefix" =>      ["foo",         "ex:suffix",            {"@value" => "ex:suffix"}],
      "integer" =>        ["foaf:age",    "54",                   {"@value" => "54", "@type" => RDF::XSD.integer.to_s}],
      "date " =>          ["dc:created",  "2011-12-27Z",          {"@value" => "2011-12-27Z", "@type" => RDF::XSD.date.to_s}],
      "native boolean" => ["foo", true,                           {"@value" => true}],
      "native integer" => ["foo", 1,                              {"@value" => 1}],
      "native double" =>  ["foo", 1.1e1,                          {"@value" => 1.1E1}],
      "native date" =>    ["foo", Date.parse("2011-12-27Z"),      {"@value" => "2011-12-27Z", "@type" => RDF::XSD.date.to_s}],
      "native time" =>    ["foo", Time.parse("10:11:12Z"),        {"@value" => "10:11:12Z", "@type" => RDF::XSD.time.to_s}],
      "native dateTime" =>["foo", DateTime.parse("2011-12-27T10:11:12Z"), {"@value" => "2011-12-27T10:11:12Z", "@type" => RDF::XSD.dateTime.to_s}],
      "rdf boolean" =>    ["foo", RDF::Literal(true),             {"@value" => "true", "@type" => RDF::XSD.boolean.to_s}],
      "rdf integer" =>    ["foo", RDF::Literal(1),                {"@value" => "1", "@type" => RDF::XSD.integer.to_s}],
      "rdf decimal" =>    ["foo", RDF::Literal::Decimal.new(1.1), {"@value" => "1.1", "@type" => RDF::XSD.decimal.to_s}],
      "rdf double" =>     ["foo", RDF::Literal::Double.new(1.1),  {"@value" => "1.1E0", "@type" => RDF::XSD.double.to_s}],
      "rdf URI" =>        ["foo", RDF::URI("foo"),                {"@id" => "foo"}],
      "rdf date " =>      ["foo", RDF::Literal(Date.parse("2011-12-27Z")), {"@value" => "2011-12-27Z", "@type" => RDF::XSD.date.to_s}],
      "rdf nonNeg" =>     ["foo", RDF::Literal::NonNegativeInteger.new(1), {"@value" => "1", "@type" => RDF::XSD.nonNegativeInteger}],
      "rdf float" =>      ["foo", RDF::Literal::Float.new(1.0), {"@value" => "1.0", "@type" => RDF::XSD.float}],
    }.each do |title, (key, compacted, expanded)|
      it title do
        subject.expand_value(key, compacted).should produce(expanded, @debug)
      end
    end

    context "@language" do
      before(:each) {subject.default_language = "en"}
      {
        "no IRI" =>         ["foo",         "http://example.com/",  {"@value" => "http://example.com/", "@language" => "en"}],
        "no term" =>        ["foo",         "ex",                   {"@value" => "ex", "@language" => "en"}],
        "no prefix" =>      ["foo",         "ex:suffix",            {"@value" => "ex:suffix", "@language" => "en"}],
        "native boolean" => ["foo",         true,                   {"@value" => true}],
        "native integer" => ["foo",         1,                      {"@value" => 1}],
        "native double" =>  ["foo",         1.1,                    {"@value" => 1.1}],
      }.each do |title, (key, compacted, expanded)|
        it title do
          subject.expand_value(key, compacted).should produce(expanded, @debug)
        end
      end
    end
    
    context "coercion" do
      before(:each) {subject.default_language = "en"}
      {
        "boolean-boolean" => ["ex:boolean", true,   {"@value" => true, "@type" => RDF::XSD.boolean.to_s}],
        "boolean-integer" => ["ex:integer", true,   {"@value" => true, "@type" => RDF::XSD.integer.to_s}],
        "boolean-double"  => ["ex:double",  true,   {"@value" => true, "@type" => RDF::XSD.double.to_s}],
        "double-boolean"  => ["ex:boolean", 1.1,    {"@value" => 1.1, "@type" => RDF::XSD.boolean.to_s}],
        "double-double"   => ["ex:double",  1.1,    {"@value" => 1.1, "@type" => RDF::XSD.double.to_s}],
        "double-integer"  => ["foaf:age",   1.1,    {"@value" => 1.1, "@type" => RDF::XSD.integer.to_s}],
        "integer-boolean" => ["ex:boolean", 1,      {"@value" => 1, "@type" => RDF::XSD.boolean.to_s}],
        "integer-double"  => ["ex:double",  1,      {"@value" => 1, "@type" => RDF::XSD.double.to_s}],
        "integer-integer" => ["foaf:age",   1,      {"@value" => 1, "@type" => RDF::XSD.integer.to_s}],
        "string-boolean"  => ["ex:boolean", "foo",  {"@value" => "foo", "@type" => RDF::XSD.boolean.to_s}],
        "string-double"   => ["ex:double",  "foo",  {"@value" => "foo", "@type" => RDF::XSD.double.to_s}],
        "string-integer"  => ["foaf:age",   "foo",  {"@value" => "foo", "@type" => RDF::XSD.integer.to_s}],
      }.each do |title, (key, compacted, expanded)|
        it title do
          subject.expand_value(key, compacted).should produce(expanded, @debug)
        end
      end
    end
  end

  describe "compact_value" do
    let(:ctx) do
      c = context.parse({
        "dc"         => RDF::DC.to_uri.to_s,
        "ex"         => "http://example.org/",
        "foaf"       => RDF::FOAF.to_uri.to_s,
        "xsd"        => RDF::XSD.to_s,
        "langmap"    => {"@id" => "http://example.com/langmap", "@container" => "@language"},
        "list"       => {"@id" => "http://example.org/list", "@container" => "@list"},
        "nolang"     => {"@id" => "http://example.org/nolang", "@language" => nil},
        "dc:created" => {"@type" => RDF::XSD.date.to_s},
        "foaf:age"   => {"@type" => RDF::XSD.integer.to_s},
        "foaf:knows" => {"@type" => "@id"},
      })
      @debug.clear
      c
    end
    subject {ctx}

    {
      "absolute IRI" =>   ["foaf:knows",  "http://example.com/",  {"@id" => "http://example.com/"}],
      "prefix:suffix" =>  ["foaf:knows",  "ex:suffix",            {"@id" => "http://example.org/suffix"}],
      "integer" =>        ["foaf:age",    "54",                   {"@value" => "54", "@type" => RDF::XSD.integer.to_s}],
      "date " =>          ["dc:created",  "2011-12-27Z",          {"@value" => "2011-12-27Z", "@type" => RDF::XSD.date.to_s}],
      "no IRI" =>         ["foo", {"@id" =>"http://example.com/"},{"@id" => "http://example.com/"}],
      "no IRI (CURIE)" => ["foo", {"@id" => RDF::FOAF.Person.to_s},       {"@id" => RDF::FOAF.Person.to_s}],
      "no boolean" =>     ["foo", {"@value" => "true", "@type" => RDF::XSD.boolean.to_s},{"@value" => "true", "@type" => RDF::XSD.boolean.to_s}],
      "no integer" =>     ["foo", {"@value" => "54", "@type" => RDF::XSD.integer.to_s},{"@value" => "54", "@type" => RDF::XSD.integer.to_s}],
      "no date " =>       ["foo", {"@value" => "2011-12-27Z", "@type" => RDF::XSD.date.to_s}, {"@value" => "2011-12-27Z", "@type" => RDF::XSD.date.to_s}],
      "no string " =>     ["foo", "string",                       {"@value" => "string"}],
      "no lang " =>       ["nolang", "string",                    {"@value" => "string"}],
      "native boolean" => ["foo", true,                           {"@value" => true}],
      "native integer" => ["foo", 1,                              {"@value" => 1}],
      "native integer(list)"=>["list", 1,                         {"@value" => 1}],
      "native double" =>  ["foo", 1.1e1,                          {"@value" => 1.1E1}],
    }.each do |title, (key, compacted, expanded)|
      it title do
        subject.compact_value(key, expanded).should produce(compacted, @debug)
      end
    end

    context "@language" do
      {
        "@id"                            => ["foo", {"@id" => "foo"},                                 {"@id" => "foo"}],
        "integer"                        => ["foo", {"@value" => "54", "@type" => RDF::XSD.integer.to_s},     {"@value" => "54", "@type" => RDF::XSD.integer.to_s}],
        "date"                           => ["foo", {"@value" => "2011-12-27Z","@type" => RDF::XSD.date.to_s},{"@value" => "2011-12-27Z", "@type" => RDF::XSD.date.to_s}],
        "no lang"                        => ["foo", {"@value" => "foo"  },                            {"@value" => "foo"}],
        "same lang"                      => ["foo", "foo",                                            {"@value" => "foo", "@language" => "en"}],
        "other lang"                     => ["foo",  {"@value" => "foo", "@language" => "bar"},       {"@value" => "foo", "@language" => "bar"}],
        "langmap"                        => ["langmap", "en",                                         {"@value" => "en", "@language" => "en"}],
        "no lang with @type coercion"    => ["dc:created", {"@value" => "foo"},                       {"@value" => "foo"}],
        "no lang with @id coercion"      => ["foaf:knows", {"@value" => "foo"},                       {"@value" => "foo"}],
        "no lang with @language=null"    => ["nolang", "string",                                      {"@value" => "string"}],
        "same lang with @type coercion"  => ["dc:created", {"@value" => "foo"},                       {"@value" => "foo"}],
        "same lang with @id coercion"    => ["foaf:knows", {"@value" => "foo"},                       {"@value" => "foo"}],
        "other lang with @type coercion" => ["dc:created", {"@value" => "foo", "@language" => "bar"}, {"@value" => "foo", "@language" => "bar"}],
        "other lang with @id coercion"   => ["foaf:knows", {"@value" => "foo", "@language" => "bar"}, {"@value" => "foo", "@language" => "bar"}],
        "native boolean"                 => ["foo", true,                                             {"@value" => true}],
        "native integer"                 => ["foo", 1,                                                {"@value" => 1}],
        "native integer(list)"           => ["list", 1,                                               {"@value" => 1}],
        "native double"                  => ["foo", 1.1e1,                                            {"@value" => 1.1E1}],
      }.each do |title, (key, compacted, expanded)|
        it title do
          subject.default_language = "en"
          subject.compact_value(key, expanded).should produce(compacted, @debug)
        end
      end
    end

    context "keywords" do
      before(:each) do
        subject.set_mapping("id", "@id")
        subject.set_mapping("type", "@type")
        subject.set_mapping("list", "@list")
        subject.set_mapping("set", "@set")
        subject.set_mapping("language", "@language")
        subject.set_mapping("literal", "@value")
      end

      {
        "@id" =>      [{"id" => "http://example.com/"},             {"@id" => "http://example.com/"}],
        "@type" =>    [{"literal" => "foo", "type" => "http://example.com/"},
                                                                    {"@value" => "foo", "@type" => "http://example.com/"}],
        "@value" =>   [{"literal" => "foo", "language" => "bar"},   {"@value" => "foo", "@language" => "bar"}],
      }.each do |title, (compacted, expanded)|
        it title do
          subject.compact_value("foo", expanded).should produce(compacted, @debug)
        end
      end
    end
  end
end
