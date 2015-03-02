module Static
  class Configuration
    attr_accessor :site_name, :pid, :host, :port, :root, :output, :css_url

    def initialize(options={})
      @site_name = "Static HTML Site"
      @pid = nil
      @host = "0.0.0.0"
      @port = "8000"
      @root = "./"
      @output = "output/"
      @css_url = "static.css"
    end
  end

  class << self
    attr_accessor :configuration

    private
    def parse_command!
      command = ARGV.shift
      if command =~ /\w+:\w+/
        klass, action = command.split(":")
      else
        raise "unknown command."
      end

      Static.const_get(klass.capitalize).new.send(action)
    end
  end

  def self.help!
    puts <<-EOS
mruby-static:
  preview, preview:run to preview your site
  post:new to create a new post
    EOS
  end

  def self.configure(options={}, &block)
    self.configuration ||= Configuration.new(options)
    yield(configuration) if block_given?
  end

  def self.start
    begin
      parse_command!
    rescue ArgumentError
      help!
    end
  end

  class Post
    attr_accessor :document

    def new
      @document = Document.new
      @document.body = "Your content here."
      @document.title = ARGV.shift

      @document.save!
    end
  end

  class Preview
    def initialize
      url = "#{Static.configuration.host}:#{Static.configuration.port}"
      puts "Starting preview at #{url}"

      @server = SimpleHttpServer.new({
        :server_ip => Static.configuration.host,
        :port  => Static.configuration.port,
        :document_root => Static.configuration.root,
      })

      build!
    end

    def run
      @server.run
    end

    private
    def build!
      Site.routes.each do |route|
        @server.location "/#{route}" do |res|
          document = Document.new
          document.body = File.read(Site.root + route)
          @server.response_body = document.to_html
          @server.create_response
        end
      end

      @server.location("/static.css") do |res|
        path = File.expand_path(Static.configuration.root + "static.css")
        @server.response_body = File.read(path)
        @server.create_response
      end
    end
  end

  class Template
    def initialize
      @renderer = ::Discount.new(Static.configuration.css_url, Static.configuration.site_name)
    end

    def render &block
      output = []
      output << @renderer.header
      output << yield if block_given?
      output << @renderer.footer
      output.join("")
    end
  end

  class Site
    attr_accessor :output_dir, :root_dir, :routes

    def self.routes
      @routes ||= Dir.entries(Static.configuration.root).select do |file|
        file =~ /.+.md/
      end
    end

    def self.output_dir
      @output_dir ||= File.expand_path(Static.configuration.output)
    end

    def self.root_dir
      @root_dir ||= File.expand_path(Static.configuration.root)
    end
  end

  class Generate
    def site
      Dir.mkdir(Site.output_dir)

      generate_posts
      generate_assets
    end

    def generate_posts
      Site.routes.each do |route|
        document = Document.new
        document.body = File.read(Site.root_dir + route)

        output =  Site.output_dir + route
        File.open(output.gsub('.md', '.html'), 'w+') do |file|
          file.write document.to_html
        end
      end
    end

    def generate_assets
      css = File.read(Site.root_dir + "static.css")
      path = Site.output_dir + "static.css"

      File.open(path, 'w+') do |file|
        file.write css
      end
    end
  end

  class Document
    attr_accessor :title, :body, :path, :filename

    def initialize
      @template = Template.new
    end

    def to_html
      "" << @template.render do
        body.to_html
      end
    end

    def path
      @path ||= Site.root_dir + filename
    end

    def filename
      @filename ||= @title.gsub(' ', '_')
    end

    def save!
      File.open("#{path}.md", 'w+') do |file|
        file.write body
      end
    end
  end
end
