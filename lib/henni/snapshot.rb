require "fileutils"
require "pathname"

module Henni
  class Snapshot
    OMIT = %w[.git .bundle vendor/bundle henni-report].freeze
    EMPTY_DIRS = %w[tmp log coverage].freeze
    FLAGS = File::FNM_PATHNAME | File::FNM_DOTMATCH | File::FNM_EXTGLOB

    def initialize(patterns)
      @patterns = patterns.map do |pattern|
        pattern = pattern.delete_prefix("./").delete_suffix("/")
        if pattern.empty? || pattern.include?("\0") || Pathname.new(pattern).absolute? || pattern.split("/").include?("..")
          raise ArgumentError, "exclude must be a project-relative glob: #{pattern.inspect}"
        end
        pattern
      end
    end

    def excluded?(path, root:)
      parts = path.split("/")
      parts.each_index.any? do |index|
        prefix = parts.take(index + 1).join("/")
        omit?(prefix) || (index.positive? && EMPTY_DIRS.include?(parts.first) &&
                         File.lstat(File.join(root, parts.first)).directory?)
      end
    end

    def copy(root, dest)
      root = File.realpath(root)
      dest = File.join(File.realpath(File.dirname(dest)), File.basename(dest))
      if root == "/" || dest == root || dest.start_with?(root + "/")
        raise ArgumentError, "temporary directory must be outside the project"
      end

      Dir.mkdir(dest)
      copy_directory(root, dest, "")
    end

    private

    def omit?(path)
      OMIT.include?(path) || @patterns.any? { |pattern| File.fnmatch?(pattern, path, FLAGS) }
    end

    def copy_directory(root, dest, relative)
      Dir.each_child(File.join(root, relative)) do |name|
        path = relative.empty? ? name : File.join(relative, name)
        next if omit?(path)

        source = File.join(root, path)
        output = File.join(dest, path)
        type = File.lstat(source).ftype
        if EMPTY_DIRS.include?(path) && type == "directory"
          Dir.mkdir(output)
          next
        end

        case type
        when "directory"
          Dir.mkdir(output)
          copy_directory(root, dest, path)
        when "file"
          FileUtils.copy_file(source, output, true)
        when "link"
          copy_link(root, path, source, output)
        when "socket", "fifo"
          warn "henni: skipping runtime endpoint #{path}"
        else
          raise ArgumentError, "unsupported project entry: #{path}"
        end
      end
    end

    def copy_link(root, path, source, output)
      resolved = Pathname.new(File.realpath(source))
      referent = resolved.relative_path_from(Pathname.new(root)).to_s
      if referent == ".." || referent.start_with?("../") || excluded?(referent, root: root)
        raise ArgumentError, "link points outside snapshot inputs: #{path}"
      end

      link = resolved.relative_path_from(Pathname.new(File.dirname(source)))
      File.symlink(link, output)
    end
  end
end
