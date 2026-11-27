require "prism"
require "digest"

module Henni
  class Planner
    REPLACEMENTS = { ">=" => ">", ">" => ">=", "<=" => "<", "<" => "<=", "==" => "!=", "!=" => "==" }.freeze

    OPERATORS = %w[comparison boolean condition integer logical arithmetic assignment method string array return_value].freeze
    LOGICAL = { "&&" => "||", "||" => "&&", "and" => "or", "or" => "and" }.freeze
    ARITHMETIC = { "+" => "-", "-" => "+", "*" => "/", "/" => "*", "%" => "*" }.freeze
    ASSIGNMENT = { "+=" => "-=", "-=" => "+=", "*=" => "/=", "/=" => "*=", "%=" => "*=" }.freeze
    METHODS = { "select" => "reject", "reject" => "select", "filter" => "reject", "any?" => "none?", "none?" => "any?",
                "all?" => "none?", "min" => "max", "max" => "min", "min_by" => "max_by", "max_by" => "min_by",
                "even?" => "odd?", "odd?" => "even?", "positive?" => "negative?", "negative?" => "positive?" }.freeze

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
          sites = []
          visit_body(node.body, method_name, scope, definitions.fetch(scope), [], sites)
          unless sites.empty?
            fingerprint = scope_fingerprint(node)
            sites.each { |site| site[:scope_fingerprint] = fingerprint }
            mutations.concat(sites)
          end
          visit(node.body, owner, singleton, definitions, mutations)
        end
      else
        node.compact_child_nodes.each { |child| visit(child, owner, singleton, definitions, mutations) }
      end
    end

    def scope_fingerprint(node)
      # A heredoc body can extend beyond the closing token of the definition.
      finish = node.location.end_offset
      if node.slice.include?("<<")
        node.breadth_first_search do |child|
          if child.respond_to?(:closing_loc) && (closing = child.closing_loc)
            finish = [finish, closing.end_offset].max
          end
          false
        end
      end
      start = node.location.start_offset
      Digest::SHA256.hexdigest(@source.byteslice(start, finish - start))
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

    def replacements(node, parent)
      case node
      when Prism::CallNode
        token = node.message_loc
        if @operators.include?("comparison") && !node.call_operator_loc && (after = REPLACEMENTS[token&.slice])
          yield "comparison", token, after
        end
        if @operators.include?("arithmetic") && node.receiver && !node.call_operator_loc &&
           node.arguments&.arguments&.size == 1 && (after = ARITHMETIC[token&.slice])
          yield "arithmetic", token, after
        end
        if @operators.include?("method") && node.receiver && node.call_operator_loc && (after = METHODS[token&.slice])
          yield "method", token, after
        end
      when Prism::LocalVariableOperatorWriteNode, Prism::InstanceVariableOperatorWriteNode,
           Prism::ClassVariableOperatorWriteNode, Prism::GlobalVariableOperatorWriteNode,
           Prism::ConstantOperatorWriteNode, Prism::ConstantPathOperatorWriteNode,
           Prism::CallOperatorWriteNode, Prism::IndexOperatorWriteNode
        token = node.binary_operator_loc
        yield "assignment", token, ASSIGNMENT[token.slice] if @operators.include?("assignment") && ASSIGNMENT.key?(token.slice)
      when Prism::TrueNode, Prism::FalseNode
        yield "boolean", node.location, node.is_a?(Prism::TrueNode) ? "false" : "true" if @operators.include?("boolean")
      when Prism::IfNode, Prism::UnlessNode
        return unless @operators.include?("condition")
        predicate = node.predicate
        # Literal predicates belong to the boolean family in every selection.
        return if predicate.is_a?(Prism::TrueNode) || predicate.is_a?(Prism::FalseNode)
        # Removing an opener while leaving its heredoc body can expose unrelated Ruby.
        return if predicate.breadth_first_search { |child| child.respond_to?(:heredoc?) && child.heredoc? }

        breaks = predicate.slice.scan(/\r?\n/).join
        %w[true false].each do |value|
          yield "condition", predicate.location, "(#{value}#{breaks})"
        end
      when Prism::IntegerNode
        if @operators.include?("integer")
          power_base = parent.is_a?(Prism::CallNode) && parent.name == :** && parent.receiver.equal?(node)
          [node.value + 1, node.value - 1].each do |value|
            literal = if value.negative? && power_base
                        # Group the base without introducing a command-call argument list.
                        " begin #{value} end"
                      elsif !value.negative? && node.location.slice.start_with?("-", "+")
                        # The original sign can separate a keyword from its argument (return-1).
                        " #{value}"
                      else
                        value.to_s
                      end
            yield "integer", node.location, literal
          end
        end
      when Prism::AndNode, Prism::OrNode
        yield "logical", node.operator_loc, LOGICAL.fetch(node.operator_loc.slice) if @operators.include?("logical")
      when Prism::StringNode
        if @operators.include?("string") && node.opening_loc && ["'", '"'].include?(node.opening_loc.slice) &&
           node.closing_loc && !node.slice.include?("\n")
          yield "string", node.location, node.unescaped.empty? ? '"henni"' : '""'
        end
      when Prism::ArrayNode
        if @operators.include?("array") && node.opening_loc&.slice == "[" && node.closing_loc&.slice == "]" &&
           !node.elements.empty? && !node.slice.include?("\n") &&
           !node.breadth_first_search { |child| child.respond_to?(:heredoc?) && child.heredoc? }
          yield "array", node.location, "[]"
        end
      when Prism::ReturnNode
        args = node.arguments&.arguments
        if @operators.include?("return_value") && args&.size == 1 && !args.first.is_a?(Prism::SplatNode) &&
           !args.first.is_a?(Prism::NilNode) && !args.first.slice.include?("\n") &&
           !args.first.breadth_first_search { |child| child.respond_to?(:heredoc?) && child.heredoc? }
          yield "return_value", args.first.location, "nil"
        end
      end
    end

    def visit_body(node, method_name, scope, definition, route, mutations, parent = nil)
      return if node.is_a?(Prism::DefNode) || node.is_a?(Prism::SingletonClassNode)

      replacements(node, parent) do |operator, token, after|
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
        visit_body(child, method_name, scope, definition, route + [i], mutations, node) if child
      end
    end
  end
end
