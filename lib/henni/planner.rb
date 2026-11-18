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
      visit(tree.value, nil, [], mutations)
      mutations
    end

    def apply(mutation)
      changed = @source.dup
      changed[mutation[:offset], mutation[:before].bytesize] = mutation[:after]
      changed
    end

    private

    def visit(node, scope, route, mutations)
      if node.is_a?(Prism::DefNode)
        visit(node.body, node.name.to_s.encode("UTF-8"), route + [:body], mutations) if node.body
        return
      end
      if scope && node.is_a?(Prism::CallNode) && !node.call_operator_loc
        token = node.message_loc
        before = token&.slice
        if (after = REPLACEMENTS[before])
          id = Digest::SHA256.hexdigest([@path, scope, route.join("."), before, after].join("\0"))
          mutations << { id: id, path: @path, method: scope, line: token.start_line,
                         offset: token.start_offset, before: before, after: after }
        end
      end
      node.compact_child_nodes.each_with_index { |child, i| visit(child, scope, route + [i], mutations) }
    end
  end
end
