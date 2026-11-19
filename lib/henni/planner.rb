require "prism"
require "digest"

module Henni
  class Planner
    REPLACEMENTS = { ">=" => ">", ">" => ">=", "<=" => "<", "<" => "<=", "==" => "!=", "!=" => "==" }.freeze

    OPERATORS = %w[comparison boolean condition integer logical].freeze
    LOGICAL = { "&&" => "||", "||" => "&&", "and" => "or", "or" => "and" }.freeze

    def initialize(path, source, operators: ["comparison"])
      @operators = operators
      @path = path
      @source = source
    end

    def plan
      tree = Prism.parse(@source, filepath: @path, version: "current")
      raise ArgumentError, tree.errors.map(&:message).join(", ") unless tree.success?

      mutations = []
      visit(tree.value, nil, false, Hash.new(0), mutations)
      mutations
    end

    def apply(mutation)
      changed = @source.dup
      changed.bytesplice(mutation[:offset], mutation.fetch(:length), mutation[:after])
      changed
    end

    private

    def visit(node, owner, singleton, definitions, mutations)
      case node
      when Prism::ClassNode, Prism::ModuleNode
        namespace = qualified_name(node.constant_path.slice, owner)
        visit(node.body, namespace, false, definitions, mutations) if node.body
      when Prism::SingletonClassNode
        namespace = receiver_name(node.expression, owner)
        visit(node.body, namespace, true, definitions, mutations) if node.body
      when Prism::DefNode
        method_name = node.name.to_s.encode("UTF-8")
        namespace = node.receiver ? receiver_name(node.receiver, owner) : (owner || "Object")
        separator = node.receiver || singleton ? "." : "#"
        scope = "#{namespace}#{separator}#{method_name}"
        definitions[scope] += 1
        if node.body
          visit_body(node.body, method_name, scope, definitions.fetch(scope), [], mutations)
          visit(node.body, owner, singleton, definitions, mutations)
        end
      else
        node.compact_child_nodes.each { |child| visit(child, owner, singleton, definitions, mutations) }
      end
    end

    def receiver_name(receiver, owner)
      return owner || "Object" if receiver.is_a?(Prism::SelfNode)

      if receiver.is_a?(Prism::ConstantReadNode) || receiver.is_a?(Prism::ConstantPathNode)
        qualified_name(receiver.slice, owner)
      else
        [owner, receiver.slice.encode("UTF-8")].compact.join("::")
      end
    end

    def qualified_name(raw, owner)
      name = raw.encode("UTF-8").gsub(/\s+/, "")
      name.start_with?("::") ? name.delete_prefix("::") : [owner, name].compact.join("::")
    end

    def replacements(node)
      case node
      when Prism::CallNode
        token = node.message_loc
        if @operators.include?("comparison") && !node.call_operator_loc && (after = REPLACEMENTS[token&.slice])
          yield "comparison", token, after
        end
      when Prism::TrueNode, Prism::FalseNode
        yield "boolean", node.location, node.is_a?(Prism::TrueNode) ? "false" : "true" if @operators.include?("boolean")
      when Prism::IfNode, Prism::UnlessNode
        return unless @operators.include?("condition")
        predicate = node.predicate
        # The boolean operator already offers the same edit for a literal predicate.
        return if @operators.include?("boolean") && (predicate.is_a?(Prism::TrueNode) || predicate.is_a?(Prism::FalseNode))
        # Removing an opener while leaving its heredoc body can expose unrelated Ruby.
        return if predicate.breadth_first_search { |child| child.respond_to?(:heredoc?) && child.heredoc? }

        breaks = predicate.slice.scan(/\r?\n/).join
        %w[true false].each do |value|
          yield "condition", predicate.location, breaks.empty? ? value : "(#{value}#{breaks})"
        end
      when Prism::IntegerNode
        if @operators.include?("integer")
          [node.value + 1, node.value - 1].each { |value| yield "integer", node.location, value.to_s }
        end
      when Prism::AndNode, Prism::OrNode
        yield "logical", node.operator_loc, LOGICAL.fetch(node.operator_loc.slice) if @operators.include?("logical")
      end
    end

    def visit_body(node, method_name, scope, definition, route, mutations)
      return if node.is_a?(Prism::DefNode) || node.is_a?(Prism::SingletonClassNode)

      replacements(node) do |operator, token, after|
        before = token.slice.encode("UTF-8")
        next if after == before

        key = [@path, scope, definition, route.join("."), before, after]
        # Comparison tokens already identify their operator family in existing IDs.
        key << operator unless operator == "comparison"
        mutations << { id: Digest::SHA256.hexdigest(key.join("\0")), operator: operator, path: @path,
                       method: method_name, scope: scope, line: token.start_line, offset: token.start_offset,
                       length: token.length, before: before, after: after }
      end
      node.child_nodes.each_with_index do |child, i|
        visit_body(child, method_name, scope, definition, route + [i], mutations) if child
      end
    end
  end
end
