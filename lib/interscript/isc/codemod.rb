#!/usr/bin/env ruby
# frozen_string_literal: true

require "optparse"
require "fileutils"
require "pathname"
require "strscan"

module Interscript
  module Isc
    # Codemod: converts a legacy `.imp` (Interscript Map Presentation) file
    # into an `.isc` (Interscript/ISO Script Conversion) source file.
    #
    # The transformation is mechanical. It does not parse the .imp file's
    # semantics — it works at the token level, applying the substitutions
    # documented in <<migration-annex>> of IS 1.
    #
    # Usage:
    #   codemod-imp-to-isc <file.imp> [<file.imp>...]    # convert files in place
    #   codemod-imp-to-isc --out-dir=DIR <file.imp>...   # write to DIR
    #   cat foo.imp | codemod-imp-to-isc --stdin         # stdin→stdout
    #
    class Codemod
      # Compound authority segments that need hyphenation in their canonical
      # form per ISO 24229 §5. The .imp filename uses the un-hyphenated
      # lowercase form; the .isc system code uses the canonical hyphenated
      # upper-case form.
      AUTHORITY_FIXES = {
        "bgnpcgn" => "BGN-PCGN",
        "alalc"   => "ALA-LC",
        "elot"    => "ELOT",
        "odni"    => "ODNI",
      }.freeze

      def initialize(out_dir: nil, stdin: false, write: true)
        @out_dir = out_dir
        @stdin_mode = stdin
        @write = write
      end

      def self.run(argv)
        out_dir = nil
        stdin_mode = false
        write = true

        parser = OptionParser.new do |opts|
          opts.banner = "Usage: codemod-imp-to-isc [options] <file.imp>..."
          opts.on("--out-dir=DIR", "Write .isc files to DIR instead of in place") { |v| out_dir = v }
          opts.on("--stdin", "Read .imp from stdin, write .isc to stdout") { stdin_mode = true }
          opts.on("--dry-run", "Print converted output; do not write files") { write = false }
          opts.on("-h", "--help", "Show this help") do
            puts opts
            exit 0
          end
        end
        parser.parse!(argv)

        cm = new(out_dir: out_dir, stdin: stdin_mode, write: write)
        cm.run(argv)
      end

      def run(args)
        if @stdin_mode
          $stdout.write(convert($stdin.read, filename: "stdin"))
          return
        end

        args.each do |path|
          fail "#{path}: not a .imp file" unless path.end_with?(".imp")

          source = File.read(path, encoding: "UTF-8")
          converted = convert(source, filename: File.basename(path))

          out_path = derive_out_path(path)
          if @write
            FileUtils.mkdir_p(File.dirname(out_path))
            File.write(out_path, converted)
            $stderr.puts "#{path} -> #{out_path}"
          else
            $stdout.write(converted)
          end
        end
      end

      # Convert the source text of a .imp file to .isc text.
      def convert(source, filename:)
        @scanner = StringScanner.new(source)
        @out = +""
        @filename = filename

        convert_body
        @out
      end

      private

      def convert_body
        # 1. Emit the system wrapper, deriving the ISO 24229 code from filename.
        emit_system_open

        # 2. Walk the body, transforming constructs in place.
        until @scanner.eos?
          if @scanner.scan(/\s+/m)
            @out << @scanner.matched
          elsif @scanner.scan(/#[^\n]*/)
            # Line comment (without consuming newline)
            @out << @scanner.matched
          elsif @scanner.scan(/metadata\b/)
            @out << "metadata"
            convert_metadata_block
          elsif @scanner.scan(/tests\b/)
            @out << "tests"
            convert_tests_block
          elsif @scanner.scan(/aliases\b/)
            @out << "aliases"
            convert_aliases_block
          elsif @scanner.scan(/dependency\b/)
            convert_dependency
          elsif @scanner.scan(/stage\b/)
            @out << "stage"
            convert_stage_header
          elsif @scanner.scan(/\b(parallel|sequence|separate|deep|compose|decompose|downcase|upcase|title_case)\b/)
            @out << @scanner.matched
          elsif @scanner.scan(/\brababa\b/)
            # rababa config: "200" — special directive, pass through as comment
            rest = @scanner.scan_until(/\n/)
            @out << "# rababa directive: #{rest.chomp}\n"
          elsif @scanner.scan(/\bsub\b/)
            @out << "sub"
            convert_sub_rule
          elsif @scanner.scan(/\brun\b/)
            @out << "run "
            convert_run_rule
          elsif @scanner.scan(/\bdef_alias\b/)
            convert_def_alias
          elsif @scanner.scan(/"/)
            @out << '"'
            convert_string_literal(:double)
          elsif @scanner.scan(/'/)
            @out << "'"
            convert_string_literal(:single)
          elsif @scanner.scan(/=>/)
            # Hash rocket — used in legacy `sub "X" => "Y"`. Convert to space.
            @out << " "
          elsif @scanner.scan(/,/)
            # Trailing comma — drop in compact rule contexts, leave elsewhere.
            @out << ""
          elsif @scanner.scan(/(before|after|not_before|not_after|separator):/)
            # Drop the colon in modifier kwarg form.
            @out << "#{@scanner[1]} "
          elsif @scanner.scan(/[A-Za-z_][A-Za-z0-9_]*/)
            @out << @scanner.matched
          else
            @out << @scanner.getch
          end
        end

        emit_system_close
      end

      def emit_system_open
        code = derive_system_code(@filename)
        @out << %(system "#{code}" {\n\n)
      end

      def emit_system_close
        @out << "}\n"
      end

      def derive_system_code(filename)
        stem = filename.sub(/\.imp\z/, "")
        parts = stem.split("-")
        authority_raw = parts.shift.to_s
        authority = AUTHORITY_FIXES.fetch(authority_raw.downcase, authority_raw.upcase)
        # Remaining parts: language, source_script, target_script, [year/identifying]
        # Standard layout: auth-lang-src-tgt-id
        language = parts.shift
        source_script = parts.shift
        target_script = parts.shift
        identifying = parts.join("-")
        # Build the source spelling: "<language>-<source_script>"
        source_spelling = "#{language}-#{source_script}"
        # Title-case scripts
        [authority, source_spelling, target_script, identifying].compact.join(":")
      end

      def derive_out_path(in_path)
        base = File.basename(in_path, ".imp")
        new_name = "#{base}.isc"
        return File.join(@out_dir, new_name) if @out_dir

        File.join(File.dirname(in_path), new_name)
      end

      # -- Construct-specific converters

      def convert_metadata_block
        # Find the opening brace and consume until matching close, transforming
        # `key: value` -> `key value` and `description: |` / `notes:` heredocs.
        return unless @scanner.scan(/[ \t]*\{/)

        @out << " {"
        depth = 1

        until @scanner.eos? || depth == 0
          if @scanner.scan(/\{/)
            @out << "{"
            depth += 1
          elsif @scanner.scan(/\}/)
            depth -= 1
            @out << "}"
          elsif @scanner.scan(/\n[ \t]*#[^\n]*/)
            # Comment line — preserve as-is
            @out << @scanner.matched
          elsif @scanner.scan(/\n[ \t]*\n/)
            # Blank line — preserve one newline
            @out << "\n"
          elsif @scanner.scan(/([ \t]+)#[^\n]*/)
            # Comment line (after newline was consumed by blank-line handler)
            @out << "\n#{@scanner[1]}#"
          elsif @scanner.scan(/#[^\n]*\n/)
            # Comment at start of line
            @out << "#\n"
          elsif @scanner.scan(/(?:\A|\n)([ \t]+)description[ \t]*:[ \t]*\|[ \t]*\n/)
            # Heredoc form: `description: |` followed by indented body.
            indent = @scanner[1]
            @out << "\n#{indent}description {"
            convert_indented_block_until_dedent(indent)
            @out << "\n#{indent}}"
          elsif @scanner.scan(/(?:\A|\n)([ \t]+)description[ \t]*:[ \t]*\n[ \t]+"/)
            # `description:` with multi-line QUOTED value: starts with `"` on
            # next line, ends with `"` somewhere later. Capture as brace block.
            indent = @scanner[1]
            @out << "\n#{indent}description { "
            # We've already consumed the opening `"`. Read until closing `"`.
            until @scanner.eos?
              if @scanner.scan(/[^"\n]+/)
                @out << @scanner.matched
              elsif @scanner.scan(/"/)
                @out << @scanner.matched
                break
              elsif @scanner.scan(/\n[ \t]+/)
                @out << " "
              elsif @scanner.scan(/\n/)
                @out << " "
              else
                break
              end
            end
            @out << " }"
          elsif @scanner.scan(/(?:\A|\n)([ \t]+)description[ \t]*:[ \t]*\n(?![ \t]*[A-Za-z_]\w*[ \t]*:)(?![ \t]*\})[ \t]+/)
            # `description:` with unquoted value on subsequent indented line(s).
            # Negative lookahead prevents consuming next field (e.g. implementation_notes).
            indent = @scanner[1]
            @out << "\n#{indent}description { "
            until @scanner.eos?
              if @scanner.check(/\n(?:[ \t]*\n)*([ \t]{0,#{indent.length}}\S)/) ||
                 @scanner.check(/\n(?:[ \t]*\n)*[ \t]{0,#{indent.length}}\}/)
                @out << " }"
                break
              elsif @scanner.scan(/[^\n]+/)
                @out << @scanner.matched
              elsif @scanner.scan(/\n[ \t]+/)
                @out << " "
              elsif @scanner.scan(/\n[ \t]*\n/)
                @out << " "
              elsif @scanner.scan(/\n/)
                @out << " "
              else
                break
              end
            end
          elsif @scanner.scan(/(?:\A|\n)([ \t]+)notes[ \t]*:[ \t]*\[\]/)
            # `notes: []` — empty notes list
            indent = @scanner[1]
            @out << "\n#{indent}notes { }"
          elsif @scanner.scan(/(?:\A|\n)([ \t]+)notes[ \t]*:[ \t]*""/)
            # `notes: ""` — empty quoted notes value
            indent = @scanner[1]
            @out << "\n#{indent}notes { }"
          elsif @scanner.scan(/(?:\A|\n)([ \t]+)notes[ \t]*:[ \t]*\n[ \t]+"/)
            # `notes:\n      "multi-line quoted value"` — quote starts on next line
            indent = @scanner[1]
            @out << "\n#{indent}notes {\n#{indent}  note \""
            convert_quoted_note_body
            @out << "\"\n#{indent}}"
          elsif @scanner.scan(/(?:\A|\n)([ \t]+)notes[ \t]*:[ \t]*"/)
            # `notes: "X"` — single quoted-string note value
            indent = @scanner[1]
            @out << "\n#{indent}notes {\n#{indent}  note \""
            # Read until matching close quote (may span multiple lines).
            convert_quoted_note_body
            @out << "\"\n#{indent}}"
          elsif @scanner.scan(/(?:\A|\n)([ \t]+)notes[ \t]*:[ \t]*\|[ \t]*\n/)
            # Heredoc-form notes: `notes: |` followed by indented body that's
            # one big multi-line note.
            indent = @scanner[1]
            @out << "\n#{indent}notes {"
            @out << "\n#{indent}  note \""
            read_heredoc_into_string(indent)
            @out << "\""
            @out << "\n#{indent}}"
          elsif @scanner.scan(/(?:\A|\n)([ \t]+)notes[ \t]*:[ \t]*/)
            # Notes block: list of `- item` lines. Collect into a brace block.
            indent = @scanner[1]
            @out << "\n#{indent}notes {"
            convert_notes_list_until_dedent(indent)
            @out << "\n#{indent}}"
          elsif @scanner.scan(/(?:\A|\n)([ \t]+)([A-Za-z_][\w]*)[ \t]*:[ \t]*\n(?:[ \t]*#[^\n]*\n)*[ \t]*\n*([ \t]+)-[ \t]*/)
            # Multi-line list value: `field:\n    [optional comments]\n    [optional blank]\n    - item`
            indent = @scanner[1]
            field = @scanner[2]
            item_indent = @scanner[3]
            @out << "\n#{indent}#{field} {"
            @out << "\n#{item_indent}- "
            text = @scanner.scan(/[^\n]+/).to_s
            @out << escape_braces(text)
            convert_indented_block_until_dedent(indent)
            @out << "\n#{indent}}"
          elsif @scanner.scan(/(?:\A|\n)([ \t]+)([A-Za-z_][\w]*)[ \t]*:[ \t]*\n([ \t]+)(?![ \t]*(?:-|"|\[|\]|\|))(?![ \t]*$)(?![ \t]*[A-Za-z_]\w*[ \t]*:)/)
            # Multi-line unquoted text value: `field:\n    text` (not list, quote,
            # heredoc, or another field declaration at the same indent)
            indent = @scanner[1]
            field = @scanner[2]
            @out << "\n#{indent}#{field} {"
            convert_indented_block_until_dedent(indent)
            @out << "\n#{indent}}"
          elsif @scanner.scan(/(?:\A|\n)([ \t]+)([A-Za-z_][\w]*)[ \t]*:[ \t]*\|[ \t]*\n/)
            # Generic field with heredoc: `field: |\n    body`
            indent = @scanner[1]
            field = @scanner[2]
            @out << "\n#{indent}#{field} { "
            convert_indented_block_until_dedent(indent)
            @out << " }"
          elsif @scanner.scan(/(?:\A|\n)([ \t]+)([A-Za-z_][\w]*)[ \t]*:[ \t]*/)
            # key: value -> key value, only when the key is at the start of a
            # (indented) line. Use [ \t] instead of \s to avoid eating newlines.
            @out << "\n#{@scanner[1]}#{@scanner[2]} "
          elsif @scanner.scan(/"/)
            @out << '"'
          elsif @scanner.scan(/'/)
            @out << "'"
          else
            @out << @scanner.getch
          end
        end
      end

      # Consume an indented heredoc body until a non-blank line dedents at or
      # below `indent`. Blank lines within the body are preserved.
      def convert_indented_block_until_dedent(indent)
        # Look ahead through optional blank lines: if the next non-blank line
        # is dedented to indent depth <= indent.length, the heredoc ends.
        dedent_check = /\n(?:[ \t]*\n)*([ \t]{0,#{indent.length}}\S)/

        until @scanner.eos?
          if @scanner.check(dedent_check)
            return
          elsif @scanner.scan(/\n[ \t]*\n/)
            @out << @scanner.matched
          elsif @scanner.scan(/\n([ \t]+)/)
            @out << "\n#{@scanner[1]}"
          elsif @scanner.scan(/\n/)
            @out << "\n"
          elsif @scanner.scan(/[^\n]+/)
            @out << escape_braces(@scanner.matched)
          else
            @out << @scanner.getch
          end
        end
      end

      def escape_braces(text)
        text.gsub("\\", "\\\\\\\\").gsub(/[{}]/) { |c| "\\#{c}" }
      end

      # Notes list: each item begins with `- `. Convert each to `note "..."`.
      # A `- |` item is a multi-line YAML heredoc; consume subsequent indented lines.
      def convert_notes_list_until_dedent(indent)
        # A dedent is: a non-blank line whose first non-whitespace char is at
        # indent depth <= indent.length AND isn't a `-` list marker (which
        # would be another note at the same indent).
        dedent_check = /\n(?:[ \t]*\n)*([ \t]{0,#{indent.length}}[^-\s])/

        loop do
          break if @scanner.eos?

          if @scanner.check(dedent_check)
            return
          elsif @scanner.check(/\n(?:[ \t]*\n)*[ \t]{0,#{indent.length}}\}/)
            # Hit the enclosing metadata `}` (possibly after blank lines).
            return
          elsif @scanner.scan(/\n[ \t]*\n/)
            # Blank line(s) — preserve one newline. Do NOT consume the
            # indent of the next item.
            @out << "\n"
          elsif @scanner.scan(/\n([ \t]+)-[ \t]*\|(?:[ \t]*#[^\n]*)?\n/)
            # `|` heredoc form (with optional inline comment after |)
            note_indent = @scanner[1]
            @out << "\n#{note_indent}note \""
            read_heredoc_into_string(note_indent)
            @out << "\""
          elsif @scanner.scan(/\n([ \t]+)-[ \t]+/)
            # Single-line item start (possibly with continuation lines).
            note_indent = @scanner[1]
            emit_note_with_continuation(note_indent)
          elsif @scanner.scan(/([ \t]+)-[ \t]*\|(?:[ \t]*#[^\n]*)?\n/)
            # First item right after `notes:` consumed; scanner at `<indent>- |\n`.
            emit_heredoc_note(@scanner[1])
          elsif @scanner.scan(/([ \t]+)-[ \t]+/)
            # First item right after `notes:` consumed; scanner at `<indent>- item`.
            emit_note_with_continuation(@scanner[1])
          elsif @scanner.scan(/\n/)
            @out << "\n"
          else
            @out << @scanner.getch
          end
        end
      end

      def emit_heredoc_note(indent)
        @out << "\n#{indent}note \""
        read_heredoc_into_string(indent)
        @out << "\""
      end

      def emit_note_with_continuation(note_indent)
        @out << "\n#{note_indent}note \""
        text = @scanner.scan(/[^\n]+/).to_s
        # Strip YAML inline comments: "text # comment" → "text"
        text = text.sub(/\s+#.*$/, "")
        # Strip outer quotes if the YAML list item was quoted: - "text"
        text = text[1..-2] if text.start_with?('"') && text.end_with?('"')
        text = text[1..-2] if text.start_with?("'") && text.end_with?("'")
        # Also strip leading quote when text spans multiple lines (closing on later line)
        text = text[1..] if text.start_with?('"') && !text.end_with?('"')
        text = text[1..] if text.start_with?("'") && !text.end_with?("'")
        # Unescape YAML escape sequences, then re-escape for ISC
        text = text.gsub('\\"', '"').gsub("\\\\", "\\")
        @out << text.gsub('\\', '\\\\\\\\').gsub('"', '\\"').gsub("\\u", "\\\\\\\\u")
        # Consume continuation lines: any subsequent line indented deeper
        # than the `- ` marker is part of the same note. Blank lines between
        # continuations are preserved as \n.
        loop do
          if @scanner.check(/\n[ \t]{#{note_indent.length + 1},}\S/)
            # Indented continuation
            @scanner.scan(/\n([ \t]+)/)
            @out << "\\n" + @scanner[1].strip + " "
            cont = @scanner.scan(/[^\n]+/).to_s
            @out << cont.gsub('\\', '\\\\\\\\').gsub('"', '\\"').gsub("\\u", "\\\\\\\\u")
          elsif @scanner.check(/\n[ \t]*\n[ \t]{#{note_indent.length + 1},}\S/)
            # Blank line then indented continuation
            @scanner.scan(/\n[ \t]*\n([ \t]+)/)
            @out << "\\n" + @scanner[1].strip + " "
            cont = @scanner.scan(/[^\n]+/).to_s
            @out << cont.gsub('\\', '\\\\\\\\').gsub('"', '\\"').gsub("\\u", "\\\\\\\\u")
          else
            break
          end
        end
        @out << "\""
      end

      def convert_quoted_note_body
        # Read a quoted string body (already past opening quote). Continues
        # across newlines until matching unescaped `"`.
        until @scanner.eos?
          if @scanner.scan(/\\./)
            @out << @scanner.matched
          elsif @scanner.scan(/"/)
            return
          else
            c = @scanner.getch
            @out << (c == "\n" ? "\\n" : c)
          end
        end
      end

      def read_heredoc_into_string(indent)
        # Read lines that are indented deeper than `indent` (or blank). Concatenate.
        # Preserve raw indentation — the DocumentBuilder's normalize_heredoc
        # handles YAML-style dedent to match the DSL's output.
        until @scanner.eos?
          if @scanner.check(/\n(?:[ \t]*\n)*([ \t]{0,#{indent.length}}\S)/)
            return
          elsif @scanner.scan(/\n[ \t]*\n/)
            # Blank line inside heredoc — preserve as \n\n
            @out << "\\n\\n"
          elsif @scanner.scan(/\n([ \t]+[^\n]*)/)
            # Indented line — preserve raw content (indent + text)
            line = @scanner[1].to_s.gsub('"', '\\"').gsub("\\u", "\\\\\\\\u")
            @out << "\\n" + line
          elsif @scanner.scan(/\n/)
            @out << "\\n"
          elsif @scanner.scan(/([^\n]+)/)
            line = @scanner[1].gsub('"', '\\"').gsub("\\u", "\\\\\\\\u")
            @out << line
          else
            return
          end
        end
      end

      def convert_tests_block
        return unless @scanner.scan(/[ \t]*\{/)
        @out << " {"
        depth = 1
        until @scanner.eos? || depth == 0
          if @scanner.scan(/\{/)
            @out << "{"
            depth += 1
          elsif @scanner.scan(/\}/)
            depth -= 1
            @out << "}"
          elsif @scanner.scan(/#[^\n]*/)
            # Preserve comment lines verbatim
            @out << @scanner.matched
          elsif @scanner.scan(/\btest\b/)
            # `test "X", "Y"` -> `"X" -> "Y"`
            @out << ""
          elsif @scanner.scan(/,/)
            # Comma between test args -> ` -> `
            @out << " -> "
          elsif @scanner.scan(/"/)
            @out << '"'
            convert_string_literal(:double)
          elsif @scanner.scan(/'/)
            @out << "'"
            convert_string_literal(:single)
          else
            @out << @scanner.getch
          end
        end
      end

      def convert_aliases_block
        return unless @scanner.scan(/[ \t]*\{/)
        @out << " {"
        depth = 1
        until @scanner.eos? || depth == 0
          if @scanner.scan(/\{/)
            @out << "{"
            depth += 1
          elsif @scanner.scan(/\}/)
            depth -= 1
            @out << "}"
          elsif @scanner.scan(/(?:\A|\n)([ \t]+)def_alias\s+([A-Za-z_]\w*)\s*,\s*/)
            # Legacy `def_alias name, X` -> `name = X`. Capture indent + name.
            indent = @scanner[1]
            name = @scanner[2]
            @out << "\n#{indent}#{name} = "
          elsif @scanner.scan(/def_alias\s+([A-Za-z_]\w*)\s*,\s*/)
            # `def_alias name, X` at start of aliases block (no leading newline)
            @out << "#{@scanner[1]} = "
          elsif @scanner.scan(/"/)
            @out << '"'
            convert_string_literal(:double)
          elsif @scanner.scan(/'/)
            @out << "'"
            convert_string_literal(:single)
          elsif @scanner.scan(/#[^\n]*/)
            @out << @scanner.matched
          else
            @out << @scanner.getch
          end
        end
      end

      def convert_dependency
        # Forms accepted:
        #   dependency "X"                       -> dependency "X"
        #   dependency "X", as: Y                -> dependency "X" as Y
        #   dependency "X", import: true         -> dependency "X" (import dropped; isc imports via `run`)
        #   dependency "X", as: Y, import: true  -> dependency "X" as Y
        @out << "dependency"
        # Consume up to end of line/statement, handling modifiers.
        until @scanner.eos?
          if @scanner.scan(/,?\s*as\s*:\s*/)
            @out << " as "
            # Read the alias identifier
            @scanner.scan(/[A-Za-z_]\w*/) && @out << @scanner.matched
            # Continue past this; may have more modifiers
          elsif @scanner.scan(/,?\s*import\s*:\s*true/)
            # Drop `import: true` — isc handles imports via `run map.X.stage.Y`.
            # No output.
          elsif @scanner.scan(/[\n}]/)
            @scanner.unscan
            return
          elsif @scanner.scan(/"/)
            @out << '"'
            convert_string_literal(:double)
          elsif @scanner.scan(/[^\n",}]+/)
            @out << @scanner.matched
          else
            # No progress — bail to avoid infinite loop.
            @scanner.getch
          end
        end
      end

      def convert_stage_header
        # Legacy `stage {` becomes `stage main {` if no name is given.
        # `stage(translit) {` becomes `stage translit {`.
        if @scanner.scan(/\s*\(([A-Za-z_]\w*)\)\s*\{/)
          @out << " #{@scanner[1]} {"
        elsif @scanner.scan(/[ \t]*\{/)
          @out << " main {"
        elsif @scanner.scan(/\s+([A-Za-z_]\w*)\s*\{/)
          @out << " #{@scanner[1]} {"
        end
      end

      def convert_sub_rule
        # Read the rule's from, to, and optional constraints from the source.
        # The .imp form is one of:
        #   sub "X", "Y", before: Z            (positional + kwargs)
        #   sub "X" => "Y", before: Z          (hash rocket)
        #   sub "X", "Y"                        (no constraints)
        #   sub "X" + any(Y), "Z", before: W   (concat in from)
        #
        # Output: if from/to are simple (single quoted string or atom each),
        # emit compact form `sub "X" "Y"`. Otherwise emit block form:
        #   sub {
        #     from <expr>
        #     to   <expr>
        #     before <expr>
        #     ...
        #   }

        # Tokenize the rule body up to the next `\n` (rules are single-line)
        # or unindented `}`. Capture: from_expr, comma, to_expr, constraints.
        from_expr, to_expr, constraints_str = tokenize_sub_rule

        # Decide compact vs block form.
        compact_safe = single_atom?(from_expr) && single_atom?(to_expr) && constraints_str.empty?

        if compact_safe
          @out << " #{from_expr} #{to_expr}\n"
        else
          @out << " {\n"
          @out << "    from #{from_expr}\n" unless from_expr.empty?
          @out << "    to #{to_expr}\n" unless to_expr.empty?
          unless constraints_str.empty?
            constraints_str.strip.split(/(?=\b(?:before|after|not_before|not_after)\b)/).each do |c|
              @out << "    #{c.strip}\n" unless c.strip.empty?
            end
          end
          @out << "  }\n"
        end
      end

      # Tokenize a sub rule body. Returns [from, to, constraints_string].
      # Advances the scanner past the rule (consumes up to and including the
      # trailing newline).
      def tokenize_sub_rule
        # Read until end of line. Rules are single-line in .imp.
        line = @scanner.scan_until(/\n/).to_s
        # Drop the trailing newline
        line = line.chomp

        # Strip comments (# ... to end of line) but only when # is at start of
        # token (not inside a string). Walk char by char.
        line = strip_comments(line)

        # Split into tokens: handle hash rockets, commas, parens, strings.
        tokens = []
        current = +""
        in_string = nil
        paren_depth = 0

        line.each_char.with_index do |c, _i|
          if in_string
            current << c
            if c == in_string && current[-2] != "\\"
              in_string = nil
            end
          elsif c == '"' || c == "'"
            in_string = c
            current << c
          elsif c == "("
            paren_depth += 1
            current << c
          elsif c == ")"
            paren_depth -= 1
            current << c
          elsif paren_depth.zero? && (c == "," || (c == "=" && line[_i + 1] == ">"))
            tokens << current.strip
            current = +""
          else
            current << c
          end
        end
        tokens << current.strip unless current.strip.empty?

        tokens = tokens.reject { |t| t == "=>" }

        from_expr = normalize_expr(tokens.shift.to_s)
        to_expr = normalize_expr(tokens.shift.to_s)
        constraints_str = tokens.join(" ")

        constraints_str = constraints_str.gsub(/(before|after|not_before|not_after)\s*:/, '\1')

        [from_expr, to_expr, constraints_str]
      end

      # Remove `# ...` comments from a line, respecting quoted strings.
      def strip_comments(line)
        result = +""
        in_string = nil
        line.each_char do |c|
          if in_string
            result << c
            if c == in_string && result[-2] != "\\"
              in_string = nil
            end
          elsif c == '"' || c == "'"
            in_string = c
            result << c
          elsif c == "#"
            break
          else
            result << c
          end
        end
        result
      end

      # A "single atom" expression is one quoted string, `none`, `boundary`,
      # `line_start`, `line_end`, `word_boundary`, or a bare alias identifier.
      # Anything with `+`, `any(`, `capture(`, `maybe(`, or concatenation is
      # NOT a single atom.
      def single_atom?(expr)
        return false if expr.nil? || expr.empty?
        return false if expr.include?("+")
        return false if expr =~ /\b(any|capture|maybe)\s*\(/
        s = expr.strip
        return true if s =~ /\A"[^"]*"\z/ || s =~ /\A'[^']*'\z/
        return true if ["none", "boundary", "line_start", "line_end", "word_boundary"].include?(s)
        return true if s =~ /\A[a-zA-Z_][a-zA-Z0-9_]*\z/
        false
      end

      # Normalize a captured expression: drop redundant whitespace around
      # `+` operators. `sub "X" , "Y"` -> tokens ["\"X\"", "\"Y\""].
      def normalize_expr(expr)
        expr = expr.strip
        # Collapse runs of whitespace
        expr = expr.gsub(/\s+/, " ")
        # Remove space around +
        expr = expr.gsub(/\s*\+\s*/, " + ")
        expr
      end

      def convert_run_rule
        # `run map.X.stage.Y` -> preserved
        # `run stage.Y` -> preserved (without map. prefix)
        # `run map.X.stage(Y)` -> `run map.X.stage.Y`
        if @scanner.scan(/map\.([A-Za-z_]\w*)\.stage\.([A-Za-z_]\w*)/)
          @out << "map.#{@scanner[1]}.stage.#{@scanner[2]}"
        elsif @scanner.scan(/stage\.([A-Za-z_]\w*)/)
          @out << "stage.#{@scanner[1]}"
        end
      end

      def convert_def_alias
        # Handled in convert_aliases_block.
      end

      def convert_string_literal(quote_kind)
        quote_char = quote_kind == :double ? '"' : "'"
        until @scanner.eos?
          if @scanner.scan(/\\./)
            @out << @scanner.matched
          elsif @scanner.scan(Regexp.new(Regexp.escape(quote_char)))
            @out << quote_char
            return
          else
            @out << @scanner.getch
          end
        end
      end
    end
  end
end
