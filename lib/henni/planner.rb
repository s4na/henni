require "prism"
require "digest"

module Henni
  class Planner
    REPLACEMENTS = { ">=" => ">", ">" => ">=", "<=" => "<", "<" => "<=", "==" => "!=", "!=" => "==" }.freeze

    def initialize(path, source)
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
      changed.bytesplice(mutation[:offset], mutation[:before].bytesize, mutation[:after])
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

    def visit_body(node, method_name, scope, definition, route, mutations)
      return if node.is_a?(Prism::DefNode) || node.is_a?(Prism::SingletonClassNode)

      if node.is_a?(Prism::CallNode) && !node.call_operator_loc
        token = node.message_loc
        before = token&.slice
        if (after = REPLACEMENTS[before])
          id = Digest::SHA256.hexdigest([@path, scope, definition, route.join("."), before, after].join("\0"))
          mutations << { id: id, path: @path, method: method_name, scope: scope, line: token.start_line,
                         single_line: node.location.start_line == node.location.end_line,
                         offset: token.start_offset, before: before, after: after }
        end
      end
      node.child_nodes.each_with_index do |child, i|
        visit_body(child, method_name, scope, definition, route + [i], mutations) if child
      end
    end
  end
end
