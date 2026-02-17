require 'gri/config'
require 'gri/log'
require 'gri/wmain'
require 'gri/api'
require 'gri/list'
require 'gri/page'
require 'gri/cgraph'
require 'gri/clist'

module GRI
  class Cast
    TOKEN_RE = /\A[-A-Za-z0-9_.]+\z/

    def self.parse_path_info env
      if (path_info = env['PATH_INFO']) =~ %r{^/(?:list|graph)\b}
        path_info = Regexp.last_match.post_match
      end
      if path_info
        dummy, service_name, section_name, graph_name = path_info.split /\// #/
      end
      return nil, nil, nil unless [service_name, section_name, graph_name].compact.all? {|s|
        valid_token?(s)
      }
      return service_name, section_name, graph_name
    end

    def self.valid_token? str
      str.to_s =~ TOKEN_RE
    end

    def initialize
      root_dir = Config['root-dir'] ||= Config::ROOT_PATH
      log_dir = Config['log-dir'] || Config['root-dir'] + '/log'
      Log.init "#{log_dir}/#{File.basename $0}.log"
    rescue SystemCallError
      Log.init '/tmp/gricast.log'
    end

    def call env
      req = GRI::Request.new env
      params = req.params
      cast_dir = Config['cast-dir'] || (Config::ROOT_PATH + '/cast')
      if params['grp']
        cast_dir = safe_subdir(cast_dir, params['grp'])
        return [400, {}, ['Bad Request']] unless cast_dir
      end

      if (req.query_string =~ /\A(\d+),(\d+)\z/)
        app = Page.new :dirs=>[cast_dir], :clicked=>true, :imgx=>$1, :imgy=>$2
      elsif params['r'] or params['tag']
        if params['stime']
          app = Graph.new :dirs=>[cast_dir]
        else
          app = Page.new :dirs=>[cast_dir]
        end
      elsif params['search'].to_i == 1
        app = List.new :dirs=>[cast_dir]
      elsif
        service_name, section_name, graph_name = self.class.parse_path_info(env)
        if env['PATH_INFO'] =~ %r{^/graph/} and (!service_name or !section_name or !graph_name)
          return [400, {}, ['Bad Request']]
        end
        case env['PATH_INFO']
        when %r{^/api/}
          app = API.new
        when %r{^/graph/}
          app = Cgraph.new :dir=>cast_dir
        when %r{^/page}
          app = Page.new :dirs=>[cast_dir]
        else
          app = Clist.new :dir=>cast_dir
        end
      end
      app.call env
    end

    def safe_subdir base_dir, name
      return nil if name.blank?
      base = File.expand_path(base_dir.to_s)
      path = File.expand_path(File.join(base, name.to_s))
      return nil unless path.start_with?(base + '/')
      path
    end

    def public_dir
      File.dirname(__FILE__) + '/../../public'
    end

    def self.layout
      <<EOS
<html>
<head>
<title><%= @title %></title>
<style>
td.text-right {text-align:right;}
hr {border:none;border-top:1px #cccccc solid;}
</style>
</head>
<body>
<%= yield %>
</body>
</html>
EOS
    end
  end
end
