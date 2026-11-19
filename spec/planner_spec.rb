require "henni"

RSpec.describe Henni::Planner do
  def plan(source)
    described_class.new("lib/example.rb", source).plan
  end

  it "keeps IDs when unrelated methods are added or reordered" do
    original = <<~RUBY
      module Store
        class Sale
          def first(value) = value >= 100
          def second(value) = value != 0
        end
      end
    RUBY
    changed = <<~RUBY
      module Store
        class Sale
          def second(value) = value != 0
          def unrelated = :new
          def first(value) = value >= 100
        end
      end
    RUBY
    indexed = ->(source) { plan(source).to_h { |mutation| mutation.values_at(:scope, :id) } }
    expect(indexed.call(changed)).to eq(indexed.call(original))
    expect(indexed.call(changed).keys).to contain_exactly("Store::Sale#first", "Store::Sale#second")
  end

  it "distinguishes class and instance methods, and duplicate definitions" do
    mutations = plan(<<~RUBY)
      class A
        def f(value) = value >= 100
        def f(value) = value >= 100
        def self.f(value) = value >= 100
        class << self
          def g(value) = value >= 100
        end
      end
      class B
        def f(value) = value >= 100
      end
    RUBY
    expect(mutations.map { |mutation| mutation.fetch(:scope) }).to eq(%w[A#f A#f A.f A.g B#f])
    expect(mutations.map { |mutation| mutation.fetch(:method) }).to eq(%w[f f f g f])
    expect(mutations.map { |mutation| mutation.fetch(:id) }.uniq.size).to eq(5)
  end

  it "separates constant receivers in different lexical namespaces" do
    modules = %w[A C].map do |name|
      <<~RUBY
        module #{name}
          class B; end
          def B.f(value) = value >= 100
        end
      RUBY
    end
    indexed = ->(source) { plan(source).to_h { |mutation| mutation.values_at(:scope, :id) } }
    expect(indexed.call(modules.join).keys).to contain_exactly("A::B.f", "C::B.f")
    expect(indexed.call(modules.join)).to eq(indexed.call(modules.reverse.join))
  end

  it "generates unique byte edits for the selected operator families" do
    source = "def 試す(x, y)\n  if x &&\n     y\n    true\n  else\n    0x10\n  end\nend\n"
    planner = described_class.new("lib/example.rb", source, operators: Henni::Planner::OPERATORS)
    sites = planner.plan
    expect(sites.map { |site| site[:operator] }.tally).to eq("condition" => 2, "logical" => 1, "boolean" => 1, "integer" => 2)
    expect(sites.select { |site| site[:operator] == "integer" }.map { |site| site[:after] }).to contain_exactly("15", "17")
    expect(sites.map { |site| site[:id] }.uniq.size).to eq(sites.size)
    sites.each do |site|
      changed = planner.apply(site)
      expect(changed.count("\n")).to eq(source.count("\n"))
      expect(Prism.parse(changed).success?).to be(true)
    end
  end

  it "avoids duplicate edits to a literal predicate and handles word operators" do
    planner = described_class.new("x.rb", "def f(a,b) = (a and b unless false)", operators: Henni::Planner::OPERATORS)
    expect(planner.plan.map { |site| site.values_at(:before, :after) }).to contain_exactly(["and", "or"], ["false", "true"])
  end

  it "keeps distinct mutation sites within a single method" do
    mutations = plan("def valid(value) = value >= 1 && value <= 10")
    expect(mutations.map { |mutation| mutation.fetch(:id) }.uniq.size).to eq(2)
    expect(mutations.map { |mutation| mutation.fetch(:scope) }).to eq(["Object#valid", "Object#valid"])
  end
end
