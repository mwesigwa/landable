module Landable
  module TidyService

    class TidyError < StandardError; end

    mattr_accessor :options
    @@options = [
      # is what we have
      '-utf8',

      # two-space soft indents
      '-indent',

      # no wrapping
      '--wrap 0',

      # make some guesses about how the code should look
      '--clean true',

      # kill microsoft word crap
      '--bare true',

      # quote 'em up
      '--quote-ampersand true',

      # whitespace niceness
      '--break-before-br true',

      # allow <div ...><div ...></div></div>
      '--merge-divs false',

      # silence will fall
      '--quiet true',
      '--show-warnings false',
    ]

    # list of liquid tags that also render tags - things that we should
    # consider to be element-level, and therefore to be tidied along with the
    # rest of the dom
    mattr_accessor :liquid_elements
    @@liquid_elements = [
      'template',
      'title_tag',
      'meta_tags',
      'img_tag',
    ]


    def self.call! input
      self.call input, raise_on_error: true
    end

    def self.call input, runtime_options={}
      if not tidyable?
        raise TidyError, 'Your system doesn\'t seem to have tidy installed. Please see https://github.com/w3c/tidy-html5.'
      end

      # wrapping known liquid in a span to allow tidy to format them nicely
      input = wrap_liquid input

      # off to tidy
      output = IO.popen("tidy #{options.join(' ')}", 'r+') do |io|
        io.puts input
        io.close_write
        io.read
      end

      # 0: success
      # 1: warning
      # 2: error
      # 3: ???
      # 4: profit
      if $?.exitstatus >= 2 and runtime_options[:raise_on_error]
        raise TidyError, "Tidy exited with status #{$?} - check stderr."
      end

      # unnwrapping the liquid that we wrapped earlier
      output = unwrap_liquid output

      # create and return a Result, allowing access to specific bits of the output
      Result.new output
    end

    def self.tidyable?
      @@is_tidyable ||= Kernel.system('which tidy > /dev/null')
    end

    protected

    def self.wrap_liquid input
      output = input.dup

      output.scan(/(\s*(\{% *(?:#{liquid_elements.join('|')}) *.*?%})\s*)/).each do |match, liquid|
        # encode and stash in a div, inserted between newlines, to allow tidy
        # to nudge this element around as appropriate
        encoded = Base64.encode64(liquid).strip
        output.gsub! match, " <div data-liquid=\"#{encoded}\"></div> "
      end

      output
    end

    def self.unwrap_liquid input
      output = input.dup

      output.scan(/(<div data-liquid="(.*?)"><\/div>)/).each do |match, liquid|
        # ensure we match utf8 for utf8
        decoded = Base64.decode64(liquid).force_encoding(match.encoding)
        output.gsub! match, decoded
      end

      output
    end


    class Result < Object
      def initialize source
        @source = source
      end

      def to_s
        @source
      end

      def body
        if match = @source.match(/<body(?: [^>]*)?>(.*)<\/body>/m)
          deindent match[1]
        end
      end

      def head
        if match = @source.match(/<head>(.*)<\/head>/m)
          deindent match[1]
        end
      end

      def css
        links = head.try :scan, /<link [^>]*type=['"]text\/css['"][^>]*>/
        styles = head.try :scan, /<style[^>]*>.*?<\/style>/m
        [links.to_a, styles.to_a].flatten.join("\n\n")
      end

      protected

      def deindent string
        if match = string.match(/^([ \t]*)[^\s]/)
          string.gsub(/^#{match[1]}/, '').strip
        else
          string.strip
        end
      end
    end

  end
end