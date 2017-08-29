module RuboCop
  module Cop
    module I18n
      module GetText
        class DecorateFunctionMessage < Cop
          SUPPORTED_METHODS = ['raise', 'fail']
          SUPPORTED_DECORATORS = ['_', 'n_', 'N_']

          def on_send(node)
            method_name = node.loc.selector.source
            return if !supported_method_name?(method_name)
            _, method_name, *arg_nodes = *node
            if !arg_nodes.empty? && !already_decorated?(node) && (contains_string?(arg_nodes) || string_constant?(arg_nodes))
              if string_constant?(arg_nodes)
                message_section = arg_nodes[1]
              else
                message_section = arg_nodes[0]
              end

              detect_and_report(node, message_section, method_name)
            end
          end

          private

          def supported_method_name?(method_name)
            SUPPORTED_METHODS.include?(method_name)
          end

          def already_decorated?(node, parent = nil)
            parent ||= node

            if node.respond_to?(:loc) && node.loc.respond_to?(:selector)
              return true if SUPPORTED_DECORATORS.include?(node.loc.selector.source)
            end

            return false unless node.respond_to?(:children)

            node.children.any? { |child| already_decorated?(child, parent) }
          end

          def string_constant?(nodes)
            nodes[0].type == :const && nodes[1]
          end

          def contains_string?(nodes)
            nodes[0].inspect.include?(":str") || nodes[0].inspect.include?(":dstr")
          end

          def detect_and_report(node, message_section, method_name)
            errors = how_bad_is_it(message_section)
            return if errors.empty?
            error_message = "'#{method_name}' function, "
            errors.each do |error|
              error_message << 'message string should be decorated. ' if error == :simple
              error_message << 'message should not be a concatenated string. ' if error == :concatenation
              error_message << 'message should not be a multi-line string. ' if error == :multiline
              error_message << 'message should use correctly formatted interpolation. ' if error == :interpolation
              error_message << 'message should be decorated. ' if error == :no_decoration
            end
            add_offense(message_section, :expression, error_message)
          end

          def how_bad_is_it(message_section)
            errors = []

            errors.push :simple if message_section.str_type?
            errors.push :multiline if message_section.multiline?
            errors.push :concatenation if concatenation_offense?(message_section)
            errors.push :interpolation if interpolation_offense?(message_section)
            errors.push :no_decoration if !already_decorated?(message_section)

            # only display no_decoration, if that is the only problem.
            if errors.size > 1 && errors.include?(:no_decoration)
              errors.delete(:no_decoration)
            end
            errors
          end

          def concatenation_offense?(node, parent = nil)
            parent ||= node

            if node.respond_to?(:loc) && node.loc.respond_to?(:selector)
              return true if node.loc.selector.source == '+'
            end

            return false unless node.respond_to?(:children)

            node.children.any? { |child| concatenation_offense?(child, parent) }
          end

          def interpolation_offense?(node, parent = nil)
            parent ||= node

            return true if node.class == RuboCop::AST::Node  && node.dstr_type?

            return false unless node.respond_to?(:children)

            node.children.any? { |child| interpolation_offense?(child, parent) }
          end

          def autocorrect(node)
            if node.str_type?
              single_string_correct(node)
            elsif interpolation_offense?(node)
#              interpolation_correct(node)
            end
          end

          def single_string_correct(node)
            ->(corrector) {
              corrector.insert_before(node.source_range , "_(")
            corrector.insert_after(node.source_range , ")") }
          end

          def interpolation_correct(node)
            interpolated_values_string = ""
            count = 0
            ->(corrector) {
              node.children.each do |child|
                # dstrs are split into "str" segments and other segments.
                # The "other" segments are the interpolated values.
                if child.type == :begin
                  value = child.children[0]
                  hash_key = "value"
                  if value.type == :lvar
                    # Use the variable's name as the format key
                    hash_key = value.loc.name.source
                  else
                    # These are placeholders that will manually need to be given
                    # a descriptive name
                    hash_key << "#{count}"
                    count += 1
                  end
                  if interpolated_values_string.empty?
                    interpolated_values_string << "{ "
                  end
                  interpolated_values_string << "#{hash_key}: #{value.loc.expression.source}, "

                  # Replace interpolation with format string
                  corrector.replace(child.loc.expression, "%{#{hash_key}}")
                end
              end
              if !interpolated_values_string.empty?
                interpolated_values_string << "}"
              end
              corrector.insert_before(node.source_range, '_(')
              corrector.insert_after(node.source_range, ") % #{interpolated_values_string}")
            }
          end

        end
      end
    end
  end
end
