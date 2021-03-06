require 'sass/script/lexer'

module Sass
  module Script
    class Parser
      def initialize(str)
        @lexer = Lexer.new(str)
      end

      def parse
        assert_expr :expr
      end

      def self.parse(*args)
        new(*args).parse
      end

      private

      # Defines a simple left-associative production.
      # name is the name of the production,
      # sub is the name of the production beneath it,
      # and ops is a list of operators for this precedence level
      def self.production(name, sub, *ops)
        class_eval <<RUBY
          def #{name}
            return unless e = #{sub}
            while tok = try_tok(#{ops.map {|o| o.inspect}.join(', ')})
              e = Operation.new(e, assert_expr(#{sub.inspect}), tok.first)
            end
            e
          end
RUBY
      end

      def self.unary(op, sub)
        class_eval <<RUBY
          def unary_#{op}
            return #{sub} unless try_tok(:#{op})
            UnaryOperation.new(assert_expr(:unary_#{op}), :#{op})
          end
RUBY
      end

      production :expr, :concat, :comma

      def concat
        return unless e = or_expr
        while sub = or_expr
          e = Operation.new(e, sub, :concat)
        end
        e
      end

      production :or_expr, :and_expr, :or
      production :and_expr, :eq_or_neq, :and
      production :eq_or_neq, :relational, :eq, :neq
      production :relational, :plus_or_minus, :gt, :gte, :lt, :lte
      production :plus_or_minus, :times_div_or_mod, :plus, :minus
      production :times_div_or_mod, :unary_minus, :times, :div, :mod

      unary :minus, :unary_div
      unary :div, :unary_not # For strings, so /foo/bar works
      unary :not, :funcall

      def funcall
        return paren unless name = try_tok(:ident)
        # An identifier without arguments is just a string
        return Script::String.new(name.last) unless try_tok(:lparen)
        args = arglist || []
        assert_tok(:rparen)
        Script::Funcall.new(name.last, args)
      end

      def arglist
        return unless e = concat
        return [e] unless try_tok(:comma)
        [e, *arglist]
      end

      def paren
        return variable unless try_tok(:lparen)
        e = assert_expr(:expr)
        assert_tok(:rparen)
        return e
      end

      def variable
        return literal unless c = try_tok(:const)
        Variable.new(c.last)
      end

      def literal
        (t = try_tok(:string, :number, :color, :bool)) && (return t.last)
      end

      # It would be possible to have unified #assert and #try methods,
      # but detecting the method/token difference turns out to be quite expensive.

      def assert_expr(name)
        (e = send(name)) && (return e)
        raise Sass::SyntaxError.new("Expected expression, was #{@lexer.done? ? 'end of text' : "#{@lexer.peek.first} token"}.")
      end

      def assert_tok(*names)
        (t = try_tok(*names)) && (return t)
        raise Sass::SyntaxError.new("Expected #{names.join(' or ')} token, was #{@lexer.done? ? 'end of text' : "#{@lexer.peek.first} token"}.")
      end

      def try_tok(*names)
        peeked =  @lexer.peek
        peeked && names.include?(peeked.first) && @lexer.token
      end
    end
  end
end
