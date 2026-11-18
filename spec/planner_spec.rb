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

  it "keeps distinct mutation sites within a single method" do
    mutations = plan("def valid(value) = value >= 1 && value <= 10")
    expect(mutations.map { |mutation| mutation.fetch(:id) }.uniq.size).to eq(2)
    expect(mutations.map { |mutation| mutation.fetch(:scope) }).to eq(["Object#valid", "Object#valid"])
  end
end
